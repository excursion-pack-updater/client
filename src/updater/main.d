module updater.main;

import std.datetime;
import std.experimental.logger;
import std.stdio;
import std.string;
static import std.file;

import updater;
import updater.http;

enum VERSION_FILE = "version.txt";

class SimpleLogger: FileLogger
{
    import std.concurrency: Tid;
    import std.conv: to;
    import std.format: formattedWrite;
    
    this(File file, const LogLevel lv) @safe
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
    if(!std.file.exists(VERSION_FILE))
        return null;
    
    return std.file.readText(VERSION_FILE).strip;
}

void write_version(string newVersion)
{
    std.file.write(VERSION_FILE, newVersion);
}

void do_update()
{
    log("<update stuff>");
    //TODO
}

void update_check()
{
    log("=================================================="); //separate runs in the log file
    log("Working directory: ", std.file.getcwd);
    
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
    
    do_update;
    write_version(remoteVersion);
    info("Done!");
}

int main()
{
    debug
        LogLevel logLevel = LogLevel.all;
    else
        LogLevel logLevel = LogLevel.info;
    
    auto stdoutLogger = new SimpleLogger(stdout, logLevel);
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
