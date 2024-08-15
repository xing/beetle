# Contributing to Cucumber Ruby Core

Thank you for considering contributing to Cucumber!

If you are not sure your contribution is related to `cucumber-ruby-core`, please
consider taking a look at [`cucumber-ruby`'s CONTRIBUTING.md](https://github.com/cucumber/cucumber-ruby/blob/main/CONTRIBUTING.md) first.

## Code of Conduct

Everyone interacting in this codebase and issue tracker is expected to follow
the Cucumber [code of conduct](https://cucumber.io/conduct).

## How can I contribute?

If you just want to know how to contribute to the code of `cucumber-ruby-core`,
go to [Contribute to the code](#contribute-to-the-code).

## Report bugs and submit feature requests

The short version is:

- Try to check there is not already an issue or pull request that deals with
  your bug or request
- Explain your issue and include as much details as possible to help other
  people reproduce your problem or understand your request
- Consider submitting a pull request if you feel confident enough

You can find more details for each of these steps in the following sections.

### Look for existing issues and pull requests

Search in [the current repository][cucumber-ruby-core-issues], in the
[mono-repo][cucumber/common-issues], but also in the
[whole cucumber organization][cucumber-issues] if the problem or feature has already
been reported. If you find an issue or pull request which is still open, add
comments to it instead of opening a new one.

If you're not sure, don't hesitate to just open a new issue. We can always merge
and de-duplicate later.

### Submitting a pull request

When submitting a pull request:

- create a [draft pull request][how-to-create-a-draft-pr]
- try to follow the instructions in the [template](.github/PULL_REQUEST_TEMPLATE.md)
- if possible, [sign your commits]
- update CHANGELOG.md with your changes
- once the PR is ready, request for reviews

More info on [how to contribute to the code](#contribute-to-the-code) can be
found below.

### Opening a new issue

To open a good issue, be clear and precise.

If you report a problem, the reader must be able to reproduce it easily.
Please do your best to create a [minimal, reproducible example][minimal-reproducible-example].

Consider submitting a pull request. Even if you think you cannot fix it by
yourself, a pull request with a failing test is always welcome.

If your request is for an enhancement - a new feature - try to be specific and
support your request with referenced facts and include examples to illustrate
your proposal.

## Contribute to the code

### Development environment

Development environment for `cucumber-ruby-core` is a simple Ruby environment with
Bundler. Use a [supported Ruby version](./README.md#supported-platforms), make
sure [Bundler] is set-up, and voilà!

You can then [fork][how-to-fork] and clone the repository. If your environment
is set-up properly, the following commands should install the dependencies and
execute all the tests successfully.

```shell
bundle install
bundle exec rake
```

You can now create a branch for your changes and [submit a pull request](#submitting-a-pull-request)!

### Working with local cucumber dependencies

You may need to use local dependencies instead of released gems for `cucumber-gherkin`
or `cucumber-messages`. To do so the [`Gemfile`](./Gemfile) for `cucumber-core`
allows you to specify a local path for your gems using environment variables:

    CUCUMBER_GHERKIN_RUBY
    CUCUMBER_MESSAGES_RUBY

For example, the following would use a local version of `cucumber-gherkin` with
the `rake` command:

```shell
CUCUMBER_GHERKIN_RUBY=../common/gherkin/ruby bundle exec rake
```

In the same way, if you want to test your changes to `cucumber-core` with a local
`cucumber-ruby`, checkout [`cucumber-ruby`][cucumber-ruby] and do your tests with
`CUCUMBER_RUBY_CORE` pointing to your local `cucumber-core`:

```shell
~/cucumber-ruby-core> cd ../cucumber-ruby
~/cucumber-ruby> CUCUMBER_RUBY_CORE=../cucumber-ruby-core bundle exec rake
```

### Using a local Gemfile

A local Gemfile allows you to use your prefer set of gems for your own
development workflow, like gems dedicated to debugging. Such gems are not part
of `cucumber-ruby` standard `Gemfile`.

`Gemfile.local`, `Gemfile.local.lock` and `.bundle` have been added to
`.gitignore` so local changes cannot be accidentaly commited and pushed to the
repository.

A `Gemfile.local` may look like this:

```ruby
# Gemfile.local

# Include the regular Gemfile
eval File.read('Gemfile')

# Include your favorites development gems
group :development do
  gem 'byebug'
  gem 'pry'
  gem 'pry-byebug'

  gem 'debase', require: false
  gem 'ruby-debug-ide', require: false
end
```

Then you can execute bundler with the `--gemfile` flag:
`bundle install --gemfile Gemfile.local`, or with an environment variable:
`BUNDLE_GEMFILE=Gemfile.local bundle [COMMAND]`.

To use your local Gemfile per default, you can also execute
`bundle config set --local gemfile Gemfile.local`.

### First timer? Welcome!

Looking for something simple to begin with? Look at issues with the label
'[good first issue](https://github.com/cucumber/cucumber-ruby-core/issues?q=is%3Aopen+is%3Aissue+label%3A%22good+first+issue%22)'.

### Having trouble getting started with the code? We're here to help!

If you have trouble setting-up your development environment, or getting started
with the code, you can join us on [Slack][community-slack]. You will find there
a lot of contributors.

Full-time maintainers are also available. We would be please to have 1:1 pairing
sessions to help you getting started. Look for
[Matt Wynne](https://cucumberbdd.slack.com/team/U590XDLF3) or
[Aurélien Reeves](https://cucumberbdd.slack.com/team/U011BB95MC7) on
[Slack][community-slack].

### Additional documentation and notice

You can find additional documentation in the [docs](./docs) directory such as
(non-exhaustive list):

- [How to release cucumber-ruby-core](./docs/RELEASE_PROCESS.md) (for maintainers)
- [Overview of cucumber-ruby-core](./docs/ARCHITECTURE.md)

<!-- Links -->

[community-slack]: https://cucumberbdd.slack.com/
[cucumber/common]: https://github.com/cucumber/common
[cucumber-ruby]: https://github.com/cucumber/cucumber-ruby
[cucumber-ruby-core]: https://github.com/cucumber/cucumber-ruby-core
[cucumber-ruby-core-issues]: https://github.com/cucumber/cucumber-ruby-core/search?q=is%3Aissue
[cucumber/common-issues]: https://github.com/cucumber/common/search?q=is%3Aissue
[cucumber-issues]: https://github.com/search?q=is%3Aissue+user%3Acucumber
[how-to-create-a-draft-pr]: https://docs.github.com/github/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/about-pull-requests#draft-pull-requests
[how-to-fork]: https://docs.github.com/github/collaborating-with-pull-requests/working-with-forks/about-forks
[sign your commits]: https://docs.github.com/en/github/authenticating-to-github/managing-commit-signature-verification/signing-commits
[minimal-reproducible-example]: https://stackoverflow.com/help/minimal-reproducible-example
[Bundler]: https://bundler.io/
