I have extracted much of the build scripts for [TakeOnRules.com][1] into
`lib-takeonrules`.

This is a set of Ruby scripts intended to be included in a larger Ruby
ecosystem (hence there is no Gemfile). The scripts are run as part of the
[Hugo](https://gohugo.io) build for [TakeOnRules.com][1].

Note: These scripts reflect a snapshot of the code used for TakeOnRules and are
disassociated from the originating repository. I opted for the quick copy/paste
so that I could share the scripts.

A bit of context:

The `Rakefile` and contents of `take_on_rules` directory are both in my
`HUGO_PROJECT/lib` directory. The `Gemfile` is a copy of `HUGO_PROJECT/Gemfile`
and is included to highlight dependencies.

At this point, I do not have plans to extract the `lib` directory from my
HUGO_PROJECT, as there are several varied concerns wrapped within that lib
directory. I had originally assumed and built the HUGO_PROJECT for
TakeOnRules.com under the assumption that it would be a private repository.

[1]:https://takeonrules.com
