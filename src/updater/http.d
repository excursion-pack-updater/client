module updater.http;

import std.experimental.logger;
import std.net.curl;
import std.stdio;
import std.string;
import std.uri;

import updater;

HTTP request;

shared static this()
{
    request = HTTP(null);
}

shared static ~this()
{
    request.shutdown;
}

/++
    Downloads the file at url and saves it to destination.
+/
void download(string authFile = null)(string url, string destination)
{
    url = encode(url);
    
    info("Downloading ", url, " to ", destination);
    
    auto output = File(destination, "wb");
    request.url = url;
    request.onReceive =
        (ubyte[] data)
        {
            output.rawWrite(data);
            
            return data.length;
        }
    ;
    
    static if(authFile != null)
    {
        auto auth = getAuthentication!authFile;
        
        request.setAuthentication(auth.username, auth.password);
    }
    
    request.perform;
}

/++
    Retrieves the contents of the file at url and returns it as a string.
+/
string get(string authFile = null)(string url)
{
    url = encode(url);
    
    info("Fetching ", url);
    
    ubyte[] buffer;
    request.url = url;
    request.onReceive = 
        (ubyte[] data)
        {
            buffer ~= data;
            
            return data.length;
        }
    ;
    
    static if(authFile != null)
    {
        auto auth = getAuthentication!authFile;
        
        request.setAuthentication(auth.username, auth.password);
    }
    
    request.perform;
    
    return (cast(char[])buffer).idup;
}
