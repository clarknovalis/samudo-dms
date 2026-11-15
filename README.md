# samudo-dms

samuAgenda: [samudo](https://github.com/clarknovalis/samudo) in the bar of
[DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell). It
shows the forecast with appointments and lets you complete, flag, clock and
capture. Everything goes through the `samu` command line and its session;
it follows changes live through `samu events`.

## Installing

Needs `samu` on the `PATH`, signed in.

```sh
git clone https://github.com/clarknovalis/samudo-dms ~/.config/DankMaterialShell/plugins/samuAgenda
dms ipc call plugins enable samuAgenda
```

Then add `samudo` to the bar in the settings under bar widgets.

Settings, one widget per profile, the keys in the popout and `dms ipc`:
[desktop widget](https://github.com/clarknovalis/samudo/blob/main/docs/desktop-widget.md)
in the samudo documentation.

## License

MIT, see [LICENSE](LICENSE).
