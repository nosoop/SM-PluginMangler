# Plugin Mangler

An plugin that builds on SourceMod's plugin management system.

Basically wraps around SourceMod's `sm plugins` management subcommands with added functionality:

- Accessible by root admin users in-game as `sm_plugins` and via console additionally via
`plugins`.
- `enabled` and `disabled` subcommands are implemented similar to
[DarthNinja's Plugin Enable/Disable][sm-pluginenable] plugin to persist plugin load state
between level changes.
- `refresh_stale` reloads plugins that have been updated recently.
- Multiple plugins can be specified after generally single-plugin commands, allowing the
specified action to be applied to all of them.
	- Regular expressions are supported by passing in an argument surrounded by forward slashes
	(e.g., `plugins info /base/`).
	- Globbing is not supported.  Use regular expressions (`plugins unload /subfolder/.*/`).

[sm-pluginenable]: https://forums.alliedmods.net/showthread.php?t=182086

## Building

This project is configured for building via [Ninja][]; see `BUILD.md` for detailed
instructions on how to build it.

If you'd like to use the build system for your own projects,
[the template is available here](https://github.com/nosoop/NinjaBuild-SMPlugin).

[Ninja]: https://ninja-build.org/
