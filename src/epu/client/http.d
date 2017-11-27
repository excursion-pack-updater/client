module epu.client.http;

import std.experimental.logger;
import std.net.curl;
import std.stdio;
import std.string;
import std.uri;

import epu.client;

HTTP request;

shared static this()
{
    request = HTTP(null);
}

shared static ~this()
{
    request.shutdown;
}

private string encode(string url)
{
    import std.algorithm: canFind;
    
    //url = std.uri.encode(url);
    
    while(url.canFind("//"))
        url = url.replace("//", "/");
    
    url = url.replace("http:/", "http://");
    url = url.replace("https:/", "https://");
    
    return url;
}

/++
    Downloads the file at url and saves it to destination.
+/
void download(string url, string destination)
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
    
    request.perform;
}

/++
    Retrieves the contents of the file at url and returns it as a string.
+/
string get(string url)
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
    
    request.perform;
    
    return (cast(char[])buffer).idup;
}
