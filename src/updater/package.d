module updater;

import std.algorithm;
import std.range;
import std.string;

struct Authentication
{
    string username;
    string password;
}

string get_config(string filename)()
{
    static assert(filename != null, "Attempting to get null config!");
    
    return import(filename ~ ".txt").strip;
}

Authentication get_authentication(string filename)()
{
    string data = get_config!filename;
    auto parts = data.split("=");
    
    return Authentication(
        parts.takeOne,
        parts.dropOne.join("=")
    );
}
