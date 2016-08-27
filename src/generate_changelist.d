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
        "A": Operation.ADD,
        "M": Operation.MODIFY,
        "D": Operation.DELETE,
    ];
    operationMapping = mapping.assumeUnique;
}

enum Operation
{
    ADD,
    MODIFY,
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

Commit[] parse_commits(string[] shas)
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
                    Operation.DELETE,
                    change[1],
                );
                commit.changes ~= Change(
                    Operation.ADD,
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

JSONValue generate_json(Commit[] commits)
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
                            c => c.operation == Operation.ADD || c.operation == Operation.MODIFY
                        )
                        .map!(c => JSONValue(c.filename))
                        .array
                ),
                "delete": JSONValue(
                    commit
                        .changes
                        .filter!(
                            c => c.operation == Operation.DELETE
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
    Commit[] commits = shas.parse_commits;
    JSONValue json = commits.generate_json;

    std.file.write("changes.json", json.toString);
}
