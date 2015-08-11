module updater;

import std.algorithm;
import std.range;
import std.string;

struct Authentication
{
    string username;
    string password;
}

template config(string filename)
{
    static assert(filename != null, "Attempting to get null config!");
    
    enum config = import(filename ~ ".txt").strip;
}

Authentication get_authentication(string filename)()
{
    string data = config!filename;
    auto parts = data.split("=");
    
    return Authentication(
        parts.takeOne,
        parts.dropOne.join("=")
    );
}
