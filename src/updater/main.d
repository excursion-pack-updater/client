module updater.main;

import std.algorithm;
import std.array;
import std.datetime;
import std.experimental.logger;
import std.file;
import std.path;
import std.string;
static import std.stdio;

import updater.changelist;
import updater.http;
import updater;

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
    return get(config!"version_url").strip;
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
    Filters erroneous delete operations
+/
Change[] filterBogus(Change[] changes)
{
    static bool valid(Change c)
    {
        if(c.operation != Operation.remove)
            return true;
        
        if(!c.filename.exists)
            return false;
        
        return true;
    }
    
    return changes
        .filter!valid
        .array
    ;
}

/++
    Perform update operations
+/
void doUpdate(string localVersion, string remoteVersion)
{
    immutable commitsJson = get(config!"json_url");
    immutable changes = commitsJson
        .parse
        .calculateChanges(localVersion, remoteVersion)
        .filterBogus
        .idup
    ;
    
    infof("changes: `%s`", changes);
    
    bool[string] createdDirectories;
    
    bool trick = true;
    
    if(trick)
        return;
    
    foreach(change; changes)
    {
        switch(change.operation)
        {
            case Operation.download:
                immutable directory = change.filename.dirName;
                auto entry = directory in createdDirectories;
                
                if(!entry)
                {
                    log("mkdir -p ", directory);
                    directory.mkdirRecurse;
                    
                    createdDirectories[directory] = true;
                }
                
                download!"cgit"(
                    config!"repo_base" ~ change.filename,
                    change.filename,
                );
                
                break;
            case Operation.remove:
                info("Deleting ", change.filename);
                change.filename.remove;
                
                break;
            case Operation.rename:
                string[] files = change.filename.split("\n");
                
                infof("Renaming `%s` => `%s`", files[0], files[1]);
                rename(files[0], files[1]);
                
                break;
            case Operation.copy:
                string[] files = change.filename.split("\n");
                
                infof("Copying `%s` => `%s`", files[0], files[1]);
                copy(files[0], files[1]);
                
                break;
            default:
                assert(false);
        }
    }
}

/++
    Determine if an update is necessary and, if so, run an update
+/
void updateCheck(string[] versions)
{
    log("=================================================="); //separate runs in the log file
    log("Working directory: ", getcwd);
    
    //immutable localVersion = getLocalVersion;
    //immutable remoteVersion = getRemoteVersion;
    immutable localVersion = versions[0];
    immutable remoteVersion = versions[1];
    
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
    
    if(args.length < 3)
    {
        errorf("args pls `%s`", args);
        
        return 1;
    }
    
    try
        updateCheck(args[1 .. 3]);
    catch(Throwable err)
    {
        criticalf("Uncaught exception:\n%s", err.toString);
        
        return 1;
    }
    
    return 0;
}
