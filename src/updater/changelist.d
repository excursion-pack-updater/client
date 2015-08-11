module updater.changelist;

import std.json;

import updater.http;

enum Operation
{
    DOWNLOAD,
    DELETE,
}

struct Change
{
    Operation operation;
    string filename;
}

struct Commit
{
    string sha;
    Change[] changes = null;
}

Commit[] parse(string jsonSrc)
{
    JSONValue json = jsonSrc.parseJSON;
    Commit[] result;
    
    foreach(value; json.array)
    {
        auto commit = Commit(value["sha"].str);
        
        foreach(update; value["download"].array)
            commit.changes ~= Change(
                Operation.DOWNLOAD,
                update.str
            );
        
        foreach(update; value["delete"].array)
            commit.changes ~= Change(
                Operation.DELETE,
                update.str
            );
        
        result ~= commit;
    }
    
    return result;
}

Change[] calculate_changes(Commit[] commits, string localVersion, string remoteVersion)
{
    return null;
}
