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
            if(change[0].startsWith("R")) //rename
            {
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
            
            commit.changes ~= Change(
                operationMapping[change[0]],
                change[1]
            );
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
                        .filter!(
                            c => c.operation == Operation.remove
                        )
                        .map!(c => JSONValue(c.filename))
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
