module epu.changelist;

import std.algorithm;
import std.array;
import std.experimental.logger;
import std.json;
import std.range;

enum Operation
{
    download,
    remove,
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

/++
    Parses JSON into a list of commits.
+/
Commit[] parse(JSONValue json)
{
    Commit[] result;
    
    foreach(value; json.array)
    {
        auto commit = Commit(value["sha"].str);
        
        foreach(update; value["download"].array)
            commit.changes ~= Change(
                Operation.download,
                update.str
            );
        
        foreach(update; value["delete"].array)
            commit.changes ~= Change(
                Operation.remove,
                update.str
            );
        
        result ~= commit;
    }
    
    return result;
}

/++
    Determines what operations need to happen to update from localVersion to remoteVersion.
+/
Change[] calculateChanges(Commit[] commits, string localVersion, string remoteVersion)
{
    Operation[string] result;
    
    if(localVersion != null)
        commits = commits
            .find!(c => c.sha == localVersion)
            .dropOne
            .array
        ;
    
    foreach(commit; commits)
    {
        foreach(change; commit.changes)
            result[change.filename] = change.operation;
        
        if(commit.sha == remoteVersion)
            break;
    }
    
    return result
        .byKeyValue
        .map!((entry) => Change(entry.value, entry.key))
        .array
    ;
}
