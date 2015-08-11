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
    return get(get_config!"version_url").idup.strip;
}

string get_version()
{
    return std.file.readText(VERSION_FILE).strip();
}

void write_version(string newVersion)
{
    std.file.write(VERSION_FILE, newVersion);
}

void do_update()
{
    info("Checking for updates at ", Clock.currTime);
}

void main()
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
        do_update;
    catch(Throwable err)
    {
        criticalf("Uncaught exception:\n%s", err.toString);
    }
}
