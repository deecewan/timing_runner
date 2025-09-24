# timing-runner

Please read this fully before using the gem.

## Setup

- Add the following to your `.rspec` file

```
--require timing_runner
--format TimingRunner::Logger --out <file>
```

where `<file>` is the path to the file where you want the timing results to be
logged.

## Running Tests

Run tests with

```
bundle exec timing-runner <timing runner options> -- <rspec options>
```

`<rspec options>` is any option you'd usually pass to rspec on the command line.
See [Configuration](#configuration) for the options you can pass for
`<timing runner options>`.

The runner will read from `input-file` to get the timing data.

> [!WARNING]
> You must not use the same location for `input-file` and the output file
> specified in `.rspec`! RSpec truncates that file, so you will lose your timing
> data

## Configuration

Check the options with `bundle exec timing-runner --help`.

### Options

- `--input-file <file>`: The file where timings should be read from (required)
- `--num-runners <number>`: The number of parallel runners to use (required)
- `--runner <number`>: The index of the runner to use (required)
- `--dry-run`: If set, the tests will not be executed. The program will print
the command it _would_ run, and exit (optional)

Options can be specified on the command line or in a configuration file.

The configuration file is similar to the `.rspec` file. It lives at
`.timing-runner`. Put each command line option on a new line. Be sure to use the
same syntax as in the command line, e.g. `--input-file <file>`.

Alternatively, you can use environment variables to set the options. The format
for the environment variables is `TIMING_RUNNER_<option>`, where `<option>` is
upper case, and underscores are used instead of dashes. For example, to set the
`--input-file` option, you would use `TIMING_RUNNER_INPUT_FILE=<file>`.

To see debug output from the configuration parsing (i.e. see the configuration
result, see the source of the options) you can specify `--debug` on the command
line or the configuration file, or set the environment variable
`TIMING_RUNNER_DEBUG=true`.

Order of precedence for options is as follows:
1. Command line options
2. Environment variables
3. Configuration file

## Timing Files

The timing files are simple text files with one line per test. When running
across different agents, simply combine the timing files from all agents, and
then specify the combined file as the `--input-file` option.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
