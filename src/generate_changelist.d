module generate_changelist;

import std.algorithm;
import std.array;
import std.exception;
import std.json;
import std.process;
import std.range;
import std.stdio;
import std.string;
static import std.file;

immutable Operation[string] operationMapping;

static this()
{
    auto mapping = [
        "A": Operation.add,
        "M": Operation.modify,
        "D": Operation.remove,
    ];
    operationMapping = mapping.assumeUnique;
}

enum Operation
{
    add,
    modify,
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
    string sha;
    Change[] changes = null;
}

string git(string[] args)
{
    stderr.writefln("Running `git %s`", args.join(" "));

    args = "/usr/bin/git" ~ args;
    auto proc = pipeProcess(args, Redirect.stdout | Redirect.stderr);

    proc.pid.wait;

    string output = proc.stdout.byLine.join("\n").idup;
    string errors = proc.stderr.byLine.join("\n> ").idup;

    if(errors != null)
        stderr.writeln("> ", errors);

    return output;
}

Commit[] parseCommits(string[] shas)
{
    Commit[] result;

    foreach(sha; shas)
    {
        auto changes = git(["show", "--name-status", "--oneline", sha])
            .split("\n")
            .drop(1)
            .map!(x => x.split("\t"))
        ;
        auto commit = Commit(sha);

        foreach(change; changes)
        {
            switch(change[0][0])
            {
                //for rename/copy, operation mnemonic is followed by similarity percentage
                case 'R': //rename
                    if(change[0].drop(1) != "100")
                    {
                        //if it's not 100%, we must download the new file
                        commit.changes ~= Change(
                            Operation.remove,
                            change[1],
                        );
                        commit.changes ~= Change(
                            Operation.add,
                            change[2],
                        );
                        
                        continue;
                    }
                    else //otherwise a rename can be safely performed
                        commit.changes ~= Change(
                            Operation.rename,
                            "%s\n%s".format(change[1], change[2]),
                        );
                    
                    continue;
                case 'C': //copy
                    if(change[0].drop(1) != "100") //here, if it's not 100% we need to download
                        commit.changes ~= Change(
                            Operation.add,
                            change[2],
                        );
                    else //again, otherwise we can just copy
                        commit.changes ~= Change(
                            Operation.copy,
                            "%s\n%s".format(change[1], change[2]),
                        );
                    
                    continue;
                default:
                    auto ptr = change[0] in operationMapping;
                    
                    if(ptr is null)
                        throw new Exception("Unknown operation `%s`".format(change[0]));
                    
                    commit.changes ~= Change(
                        operationMapping[change[0]],
                        change[1]
                    );
            }
        }

        result ~= commit;
    }

    return result;
}

JSONValue generateJson(Commit[] commits)
{
    JSONValue[] result;

    foreach(index, commit; commits.retro.enumerate)
        result ~= JSONValue(
            [
                "index": JSONValue(index),
                "sha": JSONValue(commit.sha),
                "download": JSONValue(
                    commit
                        .changes
                        .filter!(
                            c => c.operation == Operation.add || c.operation == Operation.modify
                        )
                        .map!(c => JSONValue(c.filename))
                        .array
                ),
                "delete": JSONValue(
                    commit
                        .changes
                        .filter!(c => c.operation == Operation.remove)
                        .map!(c => JSONValue(c.filename))
                        .array
                ),
                "rename": JSONValue(
                    commit
                        .changes
                        .filter!(c => c.operation == Operation.rename)
                        .map!(c => JSONValue(c.filename.split("\n")))
                        .array
                ),
                "copy": JSONValue(
                    commit
                        .changes
                        .filter!(c => c.operation == Operation.copy)
                        .map!(c => JSONValue([c.filename.split("\n")]))
                        .array
                ),
            ]
        );

    return JSONValue(result);
}

void main()
{
    string branch = git(["rev-parse", "--abbrev-ref", "HEAD"]);
    string[] shas = git(["rev-list", branch]).split("\n");
    Commit[] commits = shas.parseCommits;
    JSONValue json = commits.generateJson;

    std.file.write("changes.json", json.toString);
}
