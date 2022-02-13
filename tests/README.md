## Functional Tests for Nimbella CLI 

This directory is the internal counterpart of the `tests` directory in the public `nimbella-cli`repo.  It contains the tests relevant to usage by DigitalOcean.  It uses the [bats](https://github.com/bats-core/bats-core) shell script testing tool to run sample commands against the current namespace and checks the results.  _Warning: use a current namespace that does not contain valuable information._

### Running the tests

- Install the `bats` tool.

```
npm install -g bats
```

- Install the `bats` plugin (managed as npm dev deps).

```
npm install
```

- Run the following command.

```
npm test
```

For more details see the counterpart `README.md` in the `tests` directory of the public repo.