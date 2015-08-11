module updater.http;

import std.experimental.logger;
import std.net.curl;
import std.stdio;
import std.string;

import updater;

/++
    Downloads the file at url and saves it to destination.
+/
void download(string authFile = null)(string url, string destination)
{
    info("Downloading ", url, " to ", destination);
    
    auto output = File(destination, "wb");
    auto request = HTTP(url);
    int lastPercentage = -1;
    request.onReceive =
        (ubyte[] data)
        {
            output.rawWrite(data);
            
            return data.length;
        }
    ;
    request.onProgress =
        (size_t total, size_t current, size_t _, size_t __)
        {
            if(total == 0)
                total = 1;
            
            int percentage = cast(int)(
                (current / cast(real)total) * 100
            );
            
            if(percentage != lastPercentage)
                info(
                    "    %3d%%".format(percentage) //infof screws this up for some reason
                );
            
            lastPercentage = percentage;
            
            return 0;
        }
    ;
    
    static if(authFile != null)
    {
        auto auth = get_authentication!authFile;
        
        request.setAuthentication(auth.username, auth.password);
    }
    
    request.perform;
}

/++
    Retrieves the contents of the file at url and returns it as a string.
+/
string get(string authFile = null)(string url)
{
    info("Fetching ", url);
    
    ubyte[] buffer;
    auto request = HTTP(url);
    request.onReceive = 
        (ubyte[] data)
        {
            buffer ~= data;
            
            return data.length;
        }
    ;
    
    static if(authFile != null)
    {
        auto auth = get_authentication!authFile;
        
        request.setAuthentication(auth.username, auth.password);
    }
    
    request.perform;
    
    return (cast(char[])buffer).idup;
}
