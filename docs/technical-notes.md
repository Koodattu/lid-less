# Technical notes

- Opens `IOPMrootDomain` as the current user and calls `IOConnectCallScalarMethod` with `kPMSetClamshellSleepState` (selector 12): `1` requests the lid-sleep override, `0` clears it.
- Holds a `PreventUserIdleSystemSleep` IOKit assertion during the session. This assertion alone does not prevent lid-close sleep.
- Reads `AppleClamshellState` for open/closed state and a matching Apple HID sensor's feature report 1 for lid angle. Samples every 150 ms.
- Reapplies the lid override on detected AC/battery transitions.
- Runs the power session in an unprivileged child process of the same binary. Closing the app's private pipe, including on UI crash/force quit, asks the child to restore sleep and exit. The UI attempts fallback restoration if the child fails. No launch agent, login item, daemon installation, or root access is used.

The override is **system-wide, not owned by a connection**. Do not run alongside another lid-sleep utility. It has no reliable public getter for the original override bit; clearing it restores normal policy, not an arbitrary pre-existing override. `AppleClamshellCausesSleep` is not an ownership/readback guarantee. A crash of both processes, a stuck process, or OS refusal can still leave the override set until recovery or restart.

## Recovery

Quit Lid Less and stop other lid-sleep utilities, then run:

```sh
"/Applications/Lid Less.app/Contents/MacOS/LidLess" --restore
```

For a source build, replace `/Applications` with `.build` from the repository root. This requests restoration; it does not forcibly terminate any running session. If restoration fails, restart the Mac. The app never writes persistent `SleepDisabled` preferences.

## Source references

- [Apple XNU `RootDomainUserClient.cpp`](https://github.com/apple-oss-distributions/xnu/blob/main/iokit/Kernel/RootDomainUserClient.cpp): selector dispatch, lack of an entitlement check for this operation, and connection-close behavior.
- [Apple `IOPMLibDefs.h`](https://github.com/apple-oss-distributions/xnu/blob/main/iokit/IOKit/pwr_mgt/IOPMLibDefs.h): selector constant, also present in the macOS SDK.
- [Apple `IOPMAssertionCreateWithName`](https://developer.apple.com/documentation/iokit/1557134-iopmassertioncreatewithname): idle assertion API.
- [LidAngle sensor notes](https://github.com/deepakness/LidAngle): HID matching and feature-report format. The implementation here is independently written.
- [Clamshell](https://clamshell.dev/): inspiration and the developer's description of its no-admin approach. This is an independent app, not a copy or audited reproduction of Clamshell's internals.
- [Adrafinil's hardware test notes](https://github.com/kageroumado/adrafinil/blob/main/Docs/ARCHITECTURE.md#2-sleep-blocking-mechanism): reports selector 12 returning success without preventing displayless lid sleep on macOS 26.3. This conflicts with the general premise and is why hardware verification is essential.

## Verification

```sh
swift test
".build/Lid Less.app/Contents/MacOS/LidLess" --diagnose
```

Tests use a fake power backend; they never change system sleep behavior. They cover session expiry, reopen, battery/thermal cutoffs, power transitions, partial failures, restoration retries, and gesture gating. `--diagnose` reads lid/sensor/battery status without changing sleep settings.

Hardware acceptance checklist (not automated):

1. Disconnect external displays and quit other keep-awake apps. Start a timestamp loop in Terminal: `while true; do date -u; sleep 1; done`. Do not use `caffeinate` for this test.
2. Arm manually, close the lid for 30–60 seconds, then reopen. Check for a timestamp gap and sleep events using `pmset -g log`. Repeat on battery and AC. A large gap means the override did not work on this configuration.
3. Confirm the menu returns to normal after reopening and that `pmset -g assertions` no longer lists a Lid Less assertion. Close normally without arming and verify normal sleep returns.
4. Test Option-close with a slow close, then an aborted close (arming should expire). Test plugging/unplugging power during a session.
5. With the lid open, arm and force-quit only the menu bar process. Verify the child exits and normal lid-close sleep returns. Repeat by terminating only the `--hold-worker` child; the UI should restore and report the failure.

The maintainer has reported a successful closed-lid session on one Apple Silicon Mac. The full checklist above is not yet verified across supported macOS versions and hardware. Unit tests and read-only diagnostics do not establish closed-lid functionality.
