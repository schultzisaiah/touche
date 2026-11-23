<h1 align="center">Touché</h1>

<p align="center">An alert you can't miss when your YubiKey wants a touch.</p>

Touché lives in your menu bar and watches for security key touch requests. When one comes in, a glossy card drops out from under the notch, says who's asking, and stays until you touch the key. Then it turns into a checkmark and leaves on its own.

It does what [ykding](https://github.com/onyb/ykding) does, with its own alerts instead of macOS notification banners.

## The alert

- **Who's asking**: the repo and commit subject when git is signing (with ssh-keygen or gpg), or the host and remote command when ssh is authenticating. A request you didn't start shows up as something you don't recognize, instead of training you to tap whenever the key blinks.
- **Three sizes**: Compact and Regular pills, or a Large card (the default) that adds a detail panel with the repo or remote command and the kind of key.
- **Two positions**: under the notch (the default), or the center of the screen.
- **Waiting ring** that circles until the touch lands, then closes into a full ring and a checkmark.
- **Black while waiting** in dark mode (white in light mode), whatever asked, and **mint once touched**. The menu bar key turns into a tapping hand while a request waits.
- **Pop** when a request comes in, or any macOS system sound, or none.
- **Swipe right to dismiss**, with two fingers or by dragging. The trackpad clicks at the point of no return. Pull back to cancel.
- **Every display** gets the pill, or just the one your pointer is on.
- **Screen-edge glow**, off by default.
- **Left out of screen shares and recordings**, so a call doesn't see which repo or host you're touching for.

A rebase that re-signs five commits shows five pills in a row, one per touch.

## When a request ends

| Kind | Ends when |
|---|---|
| FIDO2 | The key stops waiting, which macOS logs. Touched requests show a checkmark first. A request with no end message leaves after 35 seconds. |
| OpenPGP | The card replies to gpg. An OK reply means it was touched and shows a checkmark first. An error reply, or 5 seconds without gpg repeating its request, ends it without one. |

## Menu

Click the key in the menu bar for:

- Whether Touché is watching (it restarts `log stream` if it exits).
- The last five requests, with a checkmark on the ones that were touched.
- A preview of each kind of request.
- Size, Position, Sound, Glow Around the Screen, Show on Every Display, and Open at Login.

## How it works

The detection follows [yknotify](https://github.com/noperator/yknotify). While a key waits for a touch, macOS logs telltale messages: the kernel for FIDO2, `usbsmartcardreaderd` for OpenPGP. Touché tails `log stream` for them. For gpg it also watches for the card's reply, which is how it knows the touch landed. The messages are a heuristic, not an API, so a macOS update can change them.

The requester lookup is ported from ykding. For git signing it finds the `ssh-keygen -Y sign` or `gpg -bsau` process, takes the repo from its working directory, and reads the commit subject from the git dir. For ssh it finds `ssh-sk-helper` and reads the destination off its parent's command line. If anything fails (or the key lives in ssh-agent, whose requests carry no destination) the alert says "FIDO2 request".

## Build and install

Requires macOS 14 or later and the Swift toolchain that ships with Xcode.

```sh
./build.sh            # build build/Touché.app
./build.sh run        # build, then launch it
./build.sh install    # build, copy to /Applications, and launch (needed for Open at Login)
swift test            # detection, requester parsing, and swipe tests
```

`build/Touché.app --args --preview` plays both kinds of request on launch.

If ykding is also running, you'll get both: `brew services stop ykding`.

## Credits

Detection follows [yknotify](https://github.com/noperator/yknotify) by noperator: the log predicate and which messages mean a touch is wanted. The requester lookup and debounce timing are ported from [ykding](https://github.com/onyb/ykding), MIT License, Copyright (c) 2026 Anirudha Bose. The alert design borrows from Psst, a meeting reminder app.
