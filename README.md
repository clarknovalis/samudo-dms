# samudo-dms

**[samudo.de](https://samudo.de)** · [demo](https://demo.samudo.de) ·
[documentation](https://docs.samudo.de/en/clients/desktop-widget/) ·
[samudo on GitHub](https://github.com/clarknovalis/samudo)

samuAgenda: [samudo](https://samudo.de), self-hosted task management, in the bar of
[DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell). It
shows the forecast with appointments and lets you complete, flag, clock and
capture. Everything goes through the `samu` command line and its session;
it follows changes live through `samu events`.

## Installing

Needs `samu`, the command line of samudo, on the `PATH` and signed in to
a server: your own ([self-hosting](https://docs.samudo.de/en/running/self-hosting/))
or, to try it, the public demo:

```sh
samu login --server https://demo.samudo.de --account demo-en   # password demo4samudo
```

Then the plugin:

```sh
git clone https://github.com/clarknovalis/samudo-dms ~/.config/DankMaterialShell/plugins/samuAgenda
dms ipc call plugins enable samuAgenda
```

Then add `samudo` to the bar in the settings under bar widgets.

Settings, one widget per profile, the keys in the popout and `dms ipc`:
[desktop widget](https://docs.samudo.de/en/clients/desktop-widget/)
in the samudo documentation (also
[as Markdown](https://github.com/clarknovalis/samudo/blob/main/docs/desktop-widget.md)
in its repository).

## License

MIT, see [LICENSE](LICENSE).
