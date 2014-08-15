# Nimrod module for determining whether or not a particular user agent can fetch a URL on the Web site.
# Ported from Python's robotparser module (urllib.robotparser in Python 3).

# Written by Adam Chesak
# Released under the MIT open source license.


##
##
## ADD A SECTION OF DOCS WITH CODE EXAMPLES!!!!!


import times
import httpclient
import strutils
import sequtils
import re
import cgi
import uri


type TRobotRule* = object
    path : string
    allowance : bool
type PRobotRule = ref TRobotRule

type TRobotEntry* = object
    useragents : seq[string]
    rules : seq[PRobotRule]
type PRobotEntry* = ref TRobotEntry

type TRobotParser* = object
    entries : seq[PRobotEntry]
    disallowAll : bool
    allowAll : bool
    url : string
    lastChecked : TTime
type PRobotParser* = ref TRobotParser

proc createRobotParser(url : string = ""): PRobotParser
proc mtime(robot : PRobotParser): TTime
proc modified(robot : PRobotParser) {.noreturn.}
proc setURL(robot : PRobotParser, url : string) {.noreturn.}
proc read(robot : PRobotParser) {.noreturn.}
proc parse(robot : PRobotParser, lines : seq[string]) {.noreturn.}
proc canFetch(robot : PRobotParser, useragent : string, url : string): bool
proc `$`(robot : PRobotParser): string
proc createEntry(): PRobotEntry
proc `$`(entry : PRobotEntry): string
proc appliesTo(entry : PRobotEntry, useragent : string): bool
proc allowance(entry : PRobotEntry, filename : string): bool
proc `$`(rule : PRobotRule): string
proc createRule(path : string, allowance : bool): PRobotRule
proc appliesTo(rule : PRobotRule, filename : string): bool


proc quote(url : string): string = 
    ## Replaces special characters in url. Should have the same functionality as urllib.quote() in Python.
    
    var s : string = urlEncode(url)
    s = s.replace("%2F", "/")
    s = s.replace("%2E", ".")
    s = s.replace("%2D", "-")
    return s


proc createRobotParser*(url : string = ""): PRobotParser = 
    ## Creates a new robot parser with the specified URL.
    ##
    ## ``url`` is optional, as long as it is specified later using ``setURL()``.
    
    var r : PRobotParser = PRobotParser(entries: @[], lastChecked: getTime(), url: url, allowAll: false, disallowAll: false)
    #r.entries = @[] # This is probably a bad way of doing it. Currently it uses concat()
    return r         # from sequtils to add more as needed, but this can't be efficient.


proc mtime*(robot : PRobotParser): TTime = 
    ## Returns the time that the ``robot.txt`` file was last fetched.
    ##
    ## This is useful for long-running web spiders that need to check for new ``robots.txt`` files periodically.
    
    return robot.lastChecked


proc modified*(robot : PRobotParser) =
    ## Sets the time the ``robots.txt`` file was last fetched to the current time.
    
    robot.lastChecked = getTime()


proc setURL*(robot : PRobotParser, url : string) =
    ## Sets the URL referring to a ``robots.txt`` file.
    
    robot.url = url


proc read*(robot : PRobotParser) = 
    ## Reads the ``robots.txt`` URL and feeds it to the parser.
    
    var s : string = getContent(robot.url)
    var lines = s.splitLines()
    
    robot.parse(lines)


proc parse*(robot : PRobotParser, lines : seq[string]) = 
    ## Parses the specified lines.
    ##
    ## This is meant as an internal proc (called by ``read()``), but can also be used to parse a
    ## ``robots.txt`` file without loading a URL.
    ##
    ## Example:
    ##
    ## .. code-block:: nimrod
    ##    
    ##    var parser : PRobotParser = createParser()   # Note no URL specified.
    ##    var s : string = readFile("my_local_robots_file.txt")
    ##    var lines = s.splitLines()                   # Get the lines from a local file.
    ##    parser.parse(lines)                          # And parse them without loading from a remote server.
    ##    echo(parser.canFetch("*", "http://www.myserver.com/mypage.html") # Can now use normally.
    
    var state : int = 0
    var lineNumber : int = 0
    var entry : PRobotEntry = createEntry()
    
    for line1 in lines:
         var line : string = line1.strip()
         lineNumber += 1
         if line == "":
             if state == 1:
                 entry = createEntry()
                 state = 0
             elif state == 2:
                 robot.entries = robot.entries.concat(@[entry]) # Please tell me there's a better way to do this.
         var i : int = line.find("#")
         if i >= 0:
             line = line[0..i-1]
         line = line.strip()
         if line == "":
             continue
         var lineSeq = line.split(':')
         if len(lineSeq) > 2:
             for j in 2..high(lineSeq):
                 lineSeq[1] &= lineSeq[j]
         lineSeq[0] = lineSeq[0].strip().toLower()
         lineSeq[1] = lineSeq[1].strip()
         if lineSeq[0] == "user-agent":
             if state == 2:
                 robot.entries = robot.entries.concat(@[entry])
                 entry = createEntry()
             entry.useragents = entry.useragents.concat(@[lineSeq[1]])
             state = 1
         elif lineSeq[0] == "disallow":
             entry.rules = entry.rules.concat(@[createRule(lineSeq[1], false)])
             state = 2
         elif lineSeq[0] == "allow":
             entry.rules = entry.rules.concat(@[createRule(lineSeq[1], true)])
             #state = 2                                                             ## POSSIBLE BUGFIX: THIS ISN"T IN THE PYTHON VERSION
         if state == 2:
             robot.entries = robot.entries.concat(@[entry])
             


proc canFetch*(robot : PRobotParser, useragent : string, url : string): bool = 
    ## Returns ``true`` if the useragent is allowed to fetch ``url`` according to the rules contained in the parsed ``robots.txt`` file,
    ## and ``false`` if it is not.
    
    if robot.allowAll:
        return true
    if robot.disallowAll:
        return false
    var uri : TUri = parseUri(url)
    var newUrl : string = quote(uri.path)
    if newUrl == "":
        newUrl = "/" 
    for entry in robot.entries:
        if entry.appliesTo(useragent):
            return entry.allowance(url)
    return true


proc `$`*(robot : PRobotParser): string = 
    ## Operator to convert a PRobotParser to a string.
    
    var s : string = ""
    for entry in robot.entries:
        s &= $entry & "\n"
    return s


proc createEntry*(): PRobotEntry = 
    ## Creates a new entry.
    
    var e : PRobotEntry = PRobotEntry(useragents: @[], rules: @[])
    return e


proc `$`*(entry : PRobotEntry): string =
    ## Operator to convert a PRobotEntry to a string.
    
    var s : string = ""
    for i in entry.useragents:
        s &= "User-agent: " & i & "\n"
    for i in entry.rules:
        s &= $i & "\n"
    return s


proc appliesTo*(entry : PRobotEntry, useragent : string): bool = 
    ## Determines whether or not the entry applies to the specified agent.
    
    var useragent2 : string = useragent.split('/')[0].toLower()
    for agent in entry.useragents:
        if useragent2 == agent:
            if agent == "*":
                return true
            var agent2 : string = agent.toLower()
            if re.find(agent2, re(escapeRe(useragent2))) != -1:
                return true
    return false


proc allowance*(entry : PRobotEntry, filename : string): bool = 
    ## Determines whether or not a line is allowed.
    
    for line in entry.rules:
        if line.appliesTo(filename):
            return line.allowance
    return true


proc createRule*(path : string, allowance : bool): PRobotRule = 
    ## Creates a new rule.
    
    var r : PRobotRule = PRobotRule(path: quote(path), allowance: allowance)
    return r


proc `$`*(rule : PRobotRule): string = 
    ## Operator to convert a PRobotRule to a string.
    
    var s : string
    if rule.allowance:
        s = "Allow: "
    else:
        s = "Disallow: "
    return s & rule.path


proc appliesTo*(rule : PRobotRule, filename : string): bool = 
    ## Determines whether ``filename`` applies to the specified rule.
    
    if rule.path == "%2A": # if rule.path == "*":
        return true
    return re.match(filename, re(rule.path))


var r : PRobotParser = createRobotParser("http://www.google.com/robots.txt")
r.read()
echo(r.canFetch("*", "/news"))