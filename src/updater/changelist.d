module updater.changelist;

import std.algorithm;
import std.array;
import std.experimental.logger;
import std.json;
import std.range;
import std.string;

import updater.http;

enum Operation
{
    download,
    remove,
    rename,
    copy,
}

struct Change
{
    Operation operation;
    string filename;
}

struct Commit
{
    int index;
    string sha;
    Change[] changes = null;
}

/++
    Parses JSON into a list of commits.
+/
Commit[] parse(string jsonSrc)
{
    JSONValue json = jsonSrc.parseJSON;
    Commit[] result;
    
    foreach(value; json.array)
    {
        auto commit = Commit(cast(int)value["index"].integer, value["sha"].str);
        
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
        
        foreach(update; value["rename"].array)
            commit.changes ~= Change(
                Operation.rename,
                "%s\n%s".format(update[0].str, update[1].str)
            );
        
        foreach(update; value["copy"].array)
            commit.changes ~= Change(
                Operation.copy,
                "%s\n%s".format(update[0].str, update[1].str)
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
    
    commits = commits
        .sort!"a.index < b.index"
        .array
    ;
    
    info("commits: ", commits);
    
    foreach(commit; commits)
    {
        foreach(change; commit.changes)
        {
            infof("change on `%s`: %s", change.filename.replace("\n", "\\n"), change.operation);
            
            if(change.operation == Operation.rename)
            {
                string[] files = change.filename.split("\n");
                
                infof("removing `%s`", files[0]);
                result.remove(files[0]);
            }
            
            result[change.filename] = change.operation;
        }
        
        if(commit.sha == remoteVersion)
            break;
    }
    
    return result
        .byKeyValue
        .map!((entry) => Change(entry.value, entry.key))
        .array
    ;
}
