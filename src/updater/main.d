module updater.main;

import std.array;
import std.net.curl;
import std.stdio;
import std.string;

string get_config(string name)()
{
    return import(name ~ ".txt").strip();
}

string get_version()
{
    return null;
}

string get_remote_version()
{
    return get(get_config!"version_url").idup.strip();
}

void write_version(string newVersion)
{
    
}

void download_zip()
{
    writeln("TODO: download zip");
    /*ubyte[] buffer;
    auto request = HTTP(get_config!"zip_url.txt");
    request.onReceive = 
        (ubyte[] data)
        {
            buffer ~= data;
            
            return data.length;
        }
    ;
    
    request.setAuthentication(
        get_config!"username.txt",
        get_config!"password.txt",
    );
    request.perform;*/
}

void update()
{
    writeln("TODO: rm mods && unzip pack.zip");
}

void main()
{
    writeln("Remote version: ", get_remote_version);
}
