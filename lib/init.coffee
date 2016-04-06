{BufferedProcess, CompositeDisposable} = require "atom"
{XRegExp}   = require "xregexp"
{Process}   = require "process"

## THIS WORKS!
## hdRegex = ".+?:(?<line>\\d+):(?<col>\\d+):\\s+((?<warning>Warning:)|(?<error>))\\s*\
##          (?<message>(\\s+.*\\n)+)"

hdRegex = ".+?:(?<line>\\d+):(?<col>\\d+):((?<warning>\\s+Warning:)|(?<error>))\
          (?<message>(\\s+.*\\n)+)"

hdRegexFlags = ""

trimMessage = (str) ->
  lines  = str.split("\n")
  tlines = lines.map (l) -> l.trim()
  return tlines.join("\n")

matchError = (fp, match) ->
  line = Number(match.line) - 1
  col  = Number(match.col) - 1
  tmsg = trimMessage(match.message)
  # console.log("trim message:" + tmsg)
  type: if match.warning then "Warning" else "Error",
  text: tmsg, #match.message,
  filePath: fp,
  multiline: true,
  range: [ [line, col], [line, col + 1] ]

infoErrors = (fp, info) ->
  # console.log ("begin:" + info + ":end")
  if (!info)
    return []
  errors = []
  regex = XRegExp hdRegex #, hdRegexFlags
  for msg in info.split(/\r?\n\r?\n/)
    XRegExp.forEach msg, regex, (match, i) ->
      e = matchError(fp, match)
      # console.log("error:", e)
      errors.push(e)
  return errors

jsonErrors = (fp, message) ->
  return [] unless message?
  info = try JSON.parse message
  return [] unless info?
  info.map (error) ->
    type: 'Error',
    text: error.message,
    # html: [error.hint, "#{error.from} ==>", "#{ error.to}"].join "<br/>"
    filePath: error.file or fp,
    range: [
      # Atom expects ranges to be 0-based
      [error.startLine - 1, error.startColumn - 1],
      [error.endLine - 1, error.endColumn]
    ]

getUserHome = () ->
  p = process.platform
  v = if p == "win32" then "USERPROFILE" else "HOME"
  # console.log(p, v)
  process.env[v]

module.exports =
  config:
    liquidUseStack:
      title: "Use stack to run liquid (recommended)."
      type: "boolean"
      default: true

    liquidExecutablePath:
      title: "The liquid executable path."
      type: "string"
      default: "liquid"

  activate: ->
    @subscriptions = new CompositeDisposable
    @subscriptions.add atom.config.observe "linter-liquidhaskell.liquidUseStack",
      (useStack) =>
        @useStack = useStack
    @subscriptions.add atom.config.observe "linter-liquidhaskell.liquidExecutablePath",
      (executablePath) =>
        @executablePath = executablePath

  deactivate: ->
    @subscriptions.dispose()
    # TODO(SN): delete socket file?

  provideLinter: ->
    provider =
      grammarScopes: ["source.haskell"]
      scope: "file" # or "project"
      lintOnFly: true # must be false for scope: "project"
      lint: (textEditor) =>
        return new Promise (resolve, reject) =>
          filePath = textEditor.getPath()
          message  = []
          # console.log ("exec: " + @executablePath)
          # console.log ("path: " + textEditor.getPath())
          # console.log ("zog : " + getUserHome())
          command = @executablePath
          args    = [ "--json", filePath ]
          if @useStack
            command = "stack"
            args    = [ "exec", "--" ].concat(args)
          # console.warn(command, args)
          process = new BufferedProcess
            command: command
            args: args
            stderr: (data) ->
              message.push data
            stdout: (data) ->
              message.push data
            exit: (code) ->
              info = message.join("\n") # .replace(/[\r]/g, "");
              resolve jsonErrors(filePath, info)
              # if info? then resolve infoErrors(filePath, info) else resolve []

          process.onWillThrowError ({error,handle}) ->
            console.error("Failed to run", command, args, ":", message)
            reject "Failed to run #{command} with args #{args}: #{error.message}"
            handle()