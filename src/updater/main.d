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
enum VERSION_FILE = "version.txt";

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

string get_remote_version()
{
    return get(config!"version_url").strip;
}

string get_version()
{
    if(!exists(VERSION_FILE))
        return null;
    
    return readText(VERSION_FILE).strip;
}

void write_version(string newVersion)
{
    write(VERSION_FILE, newVersion);
}

/++
    Filters erroneous delete operations
+/
Change[] filter_bogus(Change[] changes)
{
    static bool valid(Change c)
    {
        if(c.operation != Operation.DELETE)
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
void do_update(string localVersion, string remoteVersion)
{
    immutable commitsJson = get(config!"json_url");
    immutable changes = commitsJson
        .parse
        .calculate_changes(localVersion, remoteVersion)
        .filter_bogus
        .idup
    ;
    bool[string] createdDirectories;
    
    foreach(change; changes)
    {
        final switch(change.operation) with(Operation)
        {
            case DOWNLOAD:
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
            case DELETE:
                info("Deleting ", change.filename);
                change.filename.remove;
                
                break;
        }
    }
}

/++
    Determine if an update is necessary and, if so, run an update
+/
void update_check()
{
    log("=================================================="); //separate runs in the log file
    log("Working directory: ", getcwd);
    
    immutable localVersion = get_version;
    immutable remoteVersion = get_remote_version;
    
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
    
    do_update(localVersion, remoteVersion);
    write_version(remoteVersion);
    info("Done!");
}

int main()
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
        update_check;
    catch(Throwable err)
    {
        criticalf("Uncaught exception:\n%s", err.toString);
        
        return 1;
    }
    
    return 0;
}
