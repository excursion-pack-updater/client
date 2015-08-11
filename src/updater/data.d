module updater.data;

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
