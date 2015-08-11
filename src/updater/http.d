module updater.http;

import std.net.curl;

import updater;

/++
    Downloads the file at url and saves it to destination.
+/
void download(string authFile = null)(string url, string destination)
{
    //TODO
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

/++
    Retrieves the contents of the file at url and returns it as a string.
+/
string get(string authFile = null)(string url)
{
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
