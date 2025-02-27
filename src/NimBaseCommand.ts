/*
 * Copyright (c) 2019 - present Nimbella Corp.
 *
 * This file is licensed to you under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License. You may obtain a copy
 * of the License at http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software distributed under
 * the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
 * OF ANY KIND, either express or implied. See the License for the specific language
 * governing permissions and limitations under the License.
 */

// Some behavior of this class was initially populated from RuntimeBaseCommand.js in
// aio-cli-plugin-runtime (translated to TypeScript), governed by the following license:

/*
Copyright 2019 Adobe Inc. All rights reserved.
This file is licensed to you under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License. You may obtain a copy
of the License at http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under
the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
OF ANY KIND, either express or implied. See the License for the specific language
governing permissions and limitations under the License.
*/

import { Command, flags } from '@oclif/command'
import { IConfig } from '@oclif/config'
import { IArg } from '@oclif/parser/lib/args'
import { format } from 'util'
import { STATUS_CODES } from 'http'
import { Feedback, authPersister, getCredentialList } from '@nimbella/nimbella-deployer'
import { reload as reloadAioConfig } from '@adobe/aio-lib-core-config'
import { GaxiosError } from 'gaxios'

import createDebug from 'debug'
const debug = createDebug('nim:base')
const verboseError = createDebug('nim:error')
const debugJSON = createDebug('nim:json')

// Schema that the 'branding' structure is expected to follow
export interface Branding {
  // The major brand
  brand: string
  // The command name
  cmdName: string
  // The default API host suffix
  defaultHostSuffix: string
  // Typical prefix on most API host names
  hostPrefix: string
  // Instructions to user to recover when there is no current namespace
  namespaceRepair: string
  // Production workbench URL (may be blank)
  workbenchURL: string
  // Preview workbench URL
  previewWorkbenchURL: string
}

// Branding.  The values here reflect the standard 'nim from Nimbella' branding.
export let branding: Branding = {
  brand: 'Nimbella',
  cmdName: 'nim',
  defaultHostSuffix: '.nimbella.io',
  hostPrefix: 'api',
  namespaceRepair: "Use 'nim logon' to create a new one or 'nim auth switch' to use an existing one",
  workbenchURL: 'https://apigcp.nimbella.io/wb',
  previewWorkbenchURL: 'https://preview-apigcp.nimbella.io/workbench'
}

// A place where workbench can store its help helper
let helpHelper: (usage: Record<string, any>) => never

// A place to store a loaded cli-ux module (lazy loaded to avoid breaking workbench)
let cli: any

// Called from workbench init
export function setHelpHelper(helper: (usage: Record<string, any>) => never): void {
  helpHelper = helper
}

// May be called from main or from a library interface to set branding
export function setBranding(newValue: Branding): void {
  branding = newValue
}

// Common behavior expected by runCommand implementations ... abstracts some features of
// oclif.Command.  The NimBaseCommand class implements this interface using its own
// methods
export interface NimLogger {
  log: (msg: string, ...args: any[]) => void
  handleError: (msg: string, err?: Error) => never
  exit: (code: number) => void // don't use 'never' here because 'exit' doesn't always exit
  displayError: (msg: string, err?: Error) => void
  logJSON: (entity: any) => void
  logTable: (data: Record<string, unknown>[], columns: Record<string, unknown>, options: Record<string, unknown>) => void
  logOutput: (json: any, msgs: string[]) => void
}

// Wrap the logger in a Feedback for using the deployer API.
export class NimFeedback implements Feedback {
  logger: NimLogger
  warnOnly: boolean
  constructor(logger: NimLogger) {
    this.logger = logger
  }

  warn(msg?: any, ...args: any[]): void {
    this.logger.log(String(msg), ...args)
  }

  progress(msg?: any, ...args: any[]): void {
    if (this.warnOnly) return
    this.logger.log(String(msg), ...args)
  }
}

// An alternative NimLogger when not using the oclif stack
export class CaptureLogger implements NimLogger {
  command: string[] // The oclif command sequence being captured (aio only)
  table: Record<string, unknown>[] // The output table (array of entity) if that kind of output was produced
  tableColumns: Record<string, unknown> // The column definition needed to format the table with cli-ux
  tableOptions: Record<string, unknown> // The options definition needed to format the table with cli-ux
  captured: string[] = [] // Captured line by line output (flowing via Logger.log)
  entity: Record<string, unknown> // An output entity if that kind of output was produced

  log(msg = '', ...args: any[]): void {
    const msgs = String(msg).split('\n')
    for (const msg of msgs) {
      this.captured.push(format(msg, ...args))
    }
  }

  handleError(msg: string, err?: Error): never {
    if (err) throw err
    msg = improveErrorMsg(msg, err)
    throw new Error(msg)
  }

  displayError(msg: string, err?: Error): void {
    msg = improveErrorMsg(msg, err)
    this.log('Error: %s', msg)
  }

  exit(_code: number): void {
    // a no-op here
  }

  logJSON(entity: Record<string, unknown>): void {
    this.entity = entity
  }

  logTable(data: Record<string, unknown>[], columns: Record<string, unknown>, options: Record<string, unknown> = {}): void {
    this.table = data
    this.tableColumns = columns
    this.tableOptions = options
  }

  logOutput(json: Record<string, unknown>, msgs: string[]): void {
    this.entity = json
    this.captured = msgs
  }
}

// Test if a supplied logger is a CaptureLogger
function isCaptureLogger(logger: NimLogger): logger is CaptureLogger {
  return 'captured' in logger
}

// Dummy stand-in for RuntimeBaseClass in aio (having an aio dependency here causes various problems with building and testing)
// This is used just as a type for type checking and is not itself instantiated (we are passed real aio classes at runtime)
class AioCommand extends Command {
  constructor(rawArgv: string[], config?: IConfig) {
    super(rawArgv, config)
  }

  handleError(_msg?: string, _err?: any) { /* no-op */ }
  parsed: { argv: string[], args: string[], flags: any }
  logJSON(_hdr: string, _entity: Record<string, unknown>) { /* no-op */ }
  table(_data: Record<string, unknown>[], _columns: Record<string, unknown>, _options: Record<string, unknown> = {}) { /* no-op */ }
  async run(_argv?: string[]) { /* no-op */ }
  setNamespaceHeaderOmission(_newValue: boolean) { /* no-op */ }
}

// The base for all our commands, including the ones that delegate to aio.  There are methods designed to be called from the
// kui repl as well as ones that implement the oclif command model.
export abstract class NimBaseCommand extends Command implements NimLogger {
  // Subclass must implement for dual invocation by kui and oclif.  Arguments are
  //  - rawArgv -- what the process would call argv
  //  - argv -- what oclif calls argv and kui calls argvNoOptions (rawArgv with flags stripped out)
  //  - args -- the args (oclif's argv) reorganized as a dictionary based on assigning names (oclif calls this 'args')
  //  - flags -- oclif's flags object (we can reuse parsedOptions for this)
  //  - logger -- the NimLogger to use
  // Our own classes ignore rawArgv.  The aio shims call runAio which needs the rawArgv, since aio classes will re-parse
  abstract runCommand(rawArgv: string[], argv: string[], args: any, flags: any, logger: NimLogger): Promise<any>

  // Saved command for the case when under a browser and various utilities need the information
  command: string[]

  // Usage model for when running with kui
  usage: Record<string, any>

  // Saved value of the --json flag from the command invocation
  useJSON: boolean

  // A general way of running help from a command.  Use _help in oclif and helpHelper in kui
  doHelp(): void {
    if (helpHelper && this.usage) {
      helpHelper(this.usage)
    } else {
      this._help()
    }
  }

  // Implement logJSON for logger interface.  Since this context assumes textual output we just
  // stringify the JSON.  Behavior is not conditioned on the useJSON variable.
  logJSON(entity: any): void {
    debugJSON('JSON logging invoked')
    const output = JSON.stringify(entity, replaceErrors, 2)
    const lines = output.split('\n')
    for (const line of lines) {
      // Bypass the shim to avoid misleading debug messages.
      super.log(line)
    }
  }

  // Implement logTable for logger interface.  This context assumes textual output, but it matters whether the
  // user requested JSON or not.  If useJSON is true, we just use the logJSON logic on the array value.  If
  // it is false, we use cli_ux to format and display the table.  That module must be lazy-loaded so that loading
  // it at module scope doesn't break the workbench (this function will not be called in the workbench since a
  // CaptureLogger will always be used).
  logTable(data: Record<string, unknown>[], columns: Record<string, unknown>, options: Record<string, unknown> = {}): void {
    if (this.useJSON) {
      this.logJSON(data)
      return
    }
    if (!cli) {
      cli = require('cli-ux').cli
    }
    cli.table(data, columns, options)
  }

  // Add a shim around Command.log to debug usage of the --json flag
  log(message = '', ...args: any[]): void {
    if (this.useJSON) {
      debugJSON('Normal log method called with --json in effect')
    }
    super.log(message, ...args)
  }

  // The logOutput command either logs JSON or normal output depending on the flag.
  // Its use by commands is optional.
  logOutput(entity: any, msgs: string[]): void {
    if (this.useJSON) {
      this.logJSON(entity)
      return
    }
    for (const msg of msgs) {
      this.log(msg)
    }
  }

  // Generic oclif run() implementation.   Parses and then invokes the abstract runCommand method
  async run(): Promise<void> {
    const { argv, args, flags } = this.parse(this.constructor as typeof NimBaseCommand)
    debug('run with rawArgv: %O, argv: %O, args: %O, flags: %O', this.argv, argv, args, flags)
    // Not clear that we should have to do the following but apparently we do.  It might be
    // a consequence of the token-ungluing/regluing that we do in main.ts.  TODO investigate.
    const bad = argv.find(arg => arg.startsWith('-'))
    if (bad) { this.handleError(`Unrecognized flag: ${bad}`) }
    // Allow for a logger to be passed in when invoked programmatically.  This only has effect on aio commands if the logger is a CaptureLogger
    interface ExtIConfig extends IConfig {
      options: {
        logger: NimLogger
      }
    }
    const options = (this.config as ExtIConfig).options
    const logger = options ? options.logger : undefined
    // Set global json flag for correct handling of tables and optional debugging of command conformance.
    this.useJSON = flags.json
    await this.runCommand(this.argv, argv, args, flags, logger || this)
    debug('runCommand returned')
  }

  // Helper used in the runCommand methods of aio shim classes.  Not used by Nimbella-sourced command classes.
  // When running under node / normal oclif, this just uses the normal run(argv) method.  But, when running under
  // kui in a browser, it takes steps to avoid a second real parse and also captures all output.  The
  // logger argument is a CaptureLogger in fact.
  async runAio(rawArgv: string[], argv: string[], args: any, flags: any, logger: NimLogger, AioClass: typeof AioCommand): Promise<void> {
    debug('runAio with rawArgv: %O, argv: %O, args: %O, flags: %O', rawArgv, argv, args, flags)
    fixAioCredentials(logger, flags)
    const cmd = new AioClass(rawArgv, {} as IConfig)
    if (flags.verbose) {
      debug('verbose flag intercepted')
      flags.verbose = false
      verboseError.enabled = true
    }
    reloadAioConfig()// The credentials fix doesn't take in the browser unless redone
    if (isCaptureLogger(logger)) {
      cmd.log = logger.log.bind(logger)
      cmd.exit = logger.exit.bind(logger)
      cmd.handleError = logger.handleError.bind(logger)
      debug('aio handleError intercepted in capture mode')
      cmd.parsed = { argv, args, flags }
      cmd.logJSON = this.makeLogJSON(logger)
      cmd.table = logger.logTable.bind(logger)
      logger.command = this.command
      debug('aio capture intercepts installed')
      cmd.setNamespaceHeaderOmission(true)
      await cmd.run()
    } else {
      cmd.handleError = this.handleError.bind(cmd)
      debug('handleError intercepted in non-capture mode')
      await cmd.run(rawArgv)
    }
  }

  // Replacement for logJSON function in RuntimeBaseCommand when running with capture
  makeLogJSON = (logger: CaptureLogger) => (_ignored: string, entity: Record<string, unknown>): void => {
    logger.entity = entity
  }

  // Generic kui runner.  Unlike run(), this gets partly pre-parsed input and doesn't do a full oclif parse.
  // It also uses the CaptureLogger so it can return the output in the forms appropriate for kui display
  // (worst case, just an array of text lines).  In addition to kui's 'argv' and 'parsedOptions' values,
  // it gets a 'skip' value (the number of arguments consumed by the command itself).
  async dispatch(argv: string[], skip: number, argTemplates: IArg<string>[], parsedOptions: any): Promise<CaptureLogger> {
    // Duplicate oclif's args parsing conventions.  Some parsing has already been done by kui
    debug('dispatch with argv: %O, skip: %d, argTemplates: %O, parsedOptions: %O', argv, skip, argTemplates, parsedOptions)
    const rawArgv = argv.slice(skip)
    this.command = argv.slice(0, skip)
    argv = parsedOptions._.slice(skip)
    if (!argTemplates) {
      argTemplates = []
    }
    const args = {} as any
    for (let i = 0; i < argTemplates.length; i++) {
      const arg = argv[i]
      if (arg) {
        args[argTemplates[i].name] = arg
      }
    }
    // Make a capture logger and run the command
    const logger = new CaptureLogger()
    debug('dispatching to runCommand with rawArgv %O, argv: %O, args: %O, flags: %O', rawArgv, argv, args, parsedOptions)
    await this.runCommand(rawArgv, argv, args, parsedOptions, logger)
    return logger
  }

  // Do oclif initialization (only used when invoked via the oclif dispatcher)
  async init(): Promise<void> {
    const { flags } = this.parse(this.constructor as typeof NimBaseCommand)

    // See https://www.npmjs.com/package/debug for usage in commands
    if (flags.verbose) {
      // verbose just sets the debug filter to nim:error
      verboseError.enabled = true
    } else if (flags.debug) {
      createDebug.enable(flags.debug)
    }
  }

  // Error handling.  This is for oclif; the CaptureLogger has a more generic implementation suitable for kui inclusion
  // Includes logic copied from Adobe I/O runtime plugin.
  handleError(msg: string, err?: any): never {
    this.parse(this.constructor as typeof NimBaseCommand)
    msg = improveErrorMsg(msg, err)
    verboseError('%O', err)
    return this.error(msg, { exit: 1 })
  }

  // For non-terminal errors.  The CaptureLogger has a simpler equivalent.
  displayError(msg: string, err?: any): void {
    this.parse(this.constructor as typeof NimBaseCommand)
    msg = improveErrorMsg(msg, err)
    verboseError('%O', err)
    return this.error(msg, { exit: false })
  }

  static args = []
  static flags = {
    debug: flags.string({ description: 'Debug level output', hidden: true }),
    verbose: flags.boolean({ char: 'v', description: 'Greater detail in error messages' }),
    help: flags.boolean({ description: 'Show help' }),
    json: flags.boolean({ description: 'Provide output in JSON form' })
  }
}

// For JSON stringify, to ensure that errors are printed
export function replaceErrors(_key: string, value: any): any {
  if (value instanceof Error) {
    const error = {}
    Object.getOwnPropertyNames(value).forEach(function(key) {
      error[key] = value[key]
    })
    return error
  }
  return value
}

// Improves an error message based on analyzing the accompanying Error object (based on similar code in RuntimeBaseCommand)
function improveErrorMsg(msg: string, err?: any): string {
  debug('Improving msg: %s, err: %O', msg, err)
  const getStatusCode = (code: number) => `${code} ${STATUS_CODES[code] || ''}`.trim()

  let pretty = ''
  if (err) {
    pretty = err.message || ''
    if (err.name === 'OpenWhiskError') {
      if (err.error && err.error.error) {
        pretty = err.error.error.toLowerCase()
        if (err.statusCode) pretty = `${pretty} (${getStatusCode(err.statusCode)})`
        else if (err.error.code) pretty = `${pretty} (${err.error.code})`
      } else if (err.statusCode) {
        pretty = getStatusCode(err.statusCode)
      }
    } else if (err instanceof GaxiosError) {
      pretty = `An error occurred communicating with Cloud Storage.
This may be a problem with your ${branding.brand} credentials.
Repeat the command with the '--verbose' flag for more detail`
    } // add more case logic here
  }
  if ((pretty || '').toString().trim()) {
    msg = msg ? `${msg}: ${pretty}` : pretty
  }
  if (!msg) {
    if (err.status) {
      msg = getStatusCode(err.status)
    } else {
      msg = 'unknown error'
    }
  }
  debug('improved msg: %s', msg)
  return msg
}

// Disambiguate a namespace name when the user ends the name with a '-' character
// If the namespace does not end with '-' just return it
// If the match is unique up to the apihost, return the unique match (possibly still ambiguous if apihost not provided)
// If there is no match, return the provided string sans '-'
// If the match is not unique up to the apihost, then
//     - if a choice prompter is provided, invoke it to get the user's choice
//     - otherwise throw an error
export async function disambiguateNamespace(namespace: string, apihost: string | undefined, choicePrompter: (list: string[]) => Promise<string>): Promise<string> {
  if (namespace.endsWith('-')) {
    namespace = namespace.slice(0, -1)
    const allCreds = await getCredentialList(authPersister)
    let matches = allCreds.filter(cred => cred.namespace.startsWith(namespace))
    if (apihost) {
      matches = matches.filter(match => match.apihost === apihost)
    }
    if (matches.length > 0) {
      if (matches.length > 1 && choicePrompter) {
        let choices: string[]
        if (apihost) {
          // Already filtered by apihost
          choices = matches.map(match => match.namespace)
        } else {
          // Might be heterogeneous by API host so include in prompt
          choices = matches.map(match => `${match.namespace} on ${match.apihost}`)
        }
        return await choicePrompter(choices)
      } else if (matches.every(cred => cred.namespace === matches[0].namespace)) {
        return matches[0].namespace
      } else {
        throw new Error(`Prefix '${namespace}' matches multiple namespaces`)
      }
    }
  }
  // No match or no '-' to begin with
  return apihost ? `${namespace} on ${apihost}` : namespace
}

// Utility to parse the value of an --apihost flag, permitting certain abbreviations
export function parseAPIHost(host: string | undefined): string | undefined {
  if (!host) {
    return undefined
  }
  if (host.includes(':')) {
    return host
  }
  if (host.includes('.')) {
    return 'https://' + host
  }
  if (branding.hostPrefix && !host.startsWith(branding.hostPrefix)) {
    host = branding.hostPrefix + host
  }
  return 'https://' + host + branding.defaultHostSuffix
}

// Stuff API host and AUTH key into the environment so that AIO does not look for these in .wskprops when invoked by nim.
// We also set AIO_RUNTIME_NAMESPACE to the wildcard '_' to guard against an actual namespace being `.wskprops` (an older
// practice now deprecated by OpenWhisk).
function fixAioCredentials(logger: NimLogger, flags: any) {
  process.env.AIO_RUNTIME_NAMESPACE = '_'
  if (flags && flags.apihost && flags.auth) {
    // No need to fix remaining credentials if complete creds are supplied on cmdline
    return
  }
  const store = authPersister.loadCredentialStoreIfPresent()
  let currentHost: string
  let currentNamespace: string
  let currentAuth: string
  if (store) {
    currentHost = store.currentHost
    currentNamespace = store.currentNamespace
  }
  if (currentHost && currentNamespace) {
    const creds = store.credentials[currentHost][currentNamespace]
    if (creds) {
      debug('have creds for current namespace')
      currentAuth = creds.api_key
    } else {
      debug(`Error retrieving credentials for '${currentNamespace}' on host '${currentHost}'`)
    }
  } else {
    logger.handleError(`You do not have a current namespace.  ${branding.namespaceRepair}`)
  }
  process.env.AIO_RUNTIME_APIHOST = currentHost
  process.env.AIO_RUNTIME_AUTH = currentAuth
}
