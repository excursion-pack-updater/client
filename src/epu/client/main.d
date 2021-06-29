module epu.client.main;

import std.algorithm;
import std.array;
import std.datetime;
import std.digest.sha;
import std.experimental.logger;
import std.file;
import std.json;
import std.path;
import std.string;
import std.typecons;
static import std.stdio;

import epu.client.http;
import epu.client;

///Where the version hash is stored
enum versionFile = "version.txt";

/++
    Logger with simple formatting
+/
class SimpleLogger: FileLogger
{
    import std.concurrency: Tid;
    import std.conv: to;
    import std.format: formattedWrite;
    
    this(std.stdio.File file, const LogLevel lv) @safe
    {
        super(file, lv);
    }
    
    override protected void beginLogMsg(
        string,
        int,
        string,
        string,
        string,
        LogLevel level,
        Tid,
        SysTime,
        Logger,
    ) @safe
    {
        formattedWrite(
            file.lockingTextWriter,
            "%8s: ",
            level.to!string.toUpper
        );
    }
}

string getRemoteVersion()
{
    return get(Config.buildURL("/version")).strip;
}

string getLocalVersion()
{
    if(!exists(versionFile))
        return null;
    
    return readText(versionFile).strip;
}

void writeVersion(string newVersion)
{
    write(versionFile, newVersion);
}

/++
    Perform update operations
+/
void doUpdate(string localVersion, string remoteVersion)
{
    import std.uni: toLower;
    
    JSONValue json = Config.buildURL("/changelist/" ~ localVersion)
        .get
        .parseJSON
    ;
    immutable downloads = json["download"]
        .array
        .map!(v => v.str)
        .array
        .idup
    ;
    immutable deletes = json["delete"]
        .array
        .map!(v => v.str)
        .array
        .idup
    ;
    immutable hashes = json["hashes"]
        .object
        .byPair
        .map!(pair => tuple(pair.key, pair.value.str.toLower))
        .assocArray
    ;
    bool[string] createdDirectories;
    
    foreach(filename; downloads)
    {
        import std.uri;
        
        immutable directory = filename.dirName;
        auto entry = directory in createdDirectories;
        
        if(!entry)
        {
            log("mkdir -p ", directory);
            directory.mkdirRecurse;
            
            createdDirectories[directory] = true;
        }
        
        if(filename.exists)
        {
            string sha = filename
                .read
                .sha1Of
                .toHexString
                .idup
                .toLower
            ;
            
            auto hashptr = filename in hashes;
            if(hashptr != null)
            {
                if(*hashptr == sha)
                {
                    infof("Skipping download of %s, file exists and hashes match", filename);
                    continue;
                }
                else
                    warningf("File %s already exists but its hash does not match. It will be overwritten (local %s, remote %s)", filename, sha, *hashptr);
            }
        }
        
        download(
            Config.buildURL("/get/" ~ encodeComponent(filename)),
            filename,
        );
    }
    
    foreach(filename; deletes)
    {
        info("Deleting ", filename);
        filename.remove;
    }
}

/++
    Determine if an update is necessary and, if so, run an update
+/
void updateCheck()
{
    log("=================================================="); //separate runs in the log file
    log("Working directory: ", getcwd);
    
    immutable localVersion = getLocalVersion;
    immutable remoteVersion = getRemoteVersion;
    
    if(remoteVersion == null)
        fatal("Remote version is missing?!");
    
    log("Local version: ", localVersion == null ? "NONE" : remoteVersion);
    log("Remote version: ", remoteVersion);
    
    if(localVersion == remoteVersion)
    {
        info("Up to date!");
        
        return;
    }
    else
        info("Update required");
    
    doUpdate(localVersion, remoteVersion);
    writeVersion(remoteVersion);
    info("Done!");
}

int main(string[] args)
{
    debug
        LogLevel logLevel = LogLevel.all;
    else
        LogLevel logLevel = LogLevel.info;
    
    auto stdoutLogger = new SimpleLogger(std.stdio.stdout, logLevel);
    auto fileLogger = new FileLogger("update.log", LogLevel.all);
    auto logger = new MultiLogger(LogLevel.all);
    
    logger.insertLogger("stdout", fileLogger);
    logger.insertLogger("file", stdoutLogger);
    
    sharedLog = logger;
    
    try
    {
        loadConfig(args[0].baseName.withExtension("ini").array);
        request.addRequestHeader("X-EPU-Key", Config.apiKey);
        updateCheck;
    }
    catch(Throwable err)
    {
        criticalf("Uncaught exception:\n%s", err.toString);
        
        return 1;
    }
    
    return 0;
}
