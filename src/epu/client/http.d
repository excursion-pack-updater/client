module epu.client.http;

import etc.c.curl;
import std.array;
import std.experimental.logger;
import std.stdio;
import std.string;
import std.uri;

import epu.client;

private CURL* curl;
private curl_slist* headers;
private Appender!(ubyte[]) recvBuf;

shared static this()
{
    curl_global_init(CurlGlobal.default_);
    curl = curl_easy_init();
    
    if(curl == null) throw new Exception("Failed to initialize cURL");
    
    curl_easy_setopt(curl, CurlOption.writefunction, &readResponse);
    curl_easy_setopt(curl, CurlOption.writedata, null);
    curl_easy_setopt(curl, CurlOption.failonerror, true);
}

shared static ~this()
{
    curl_easy_cleanup(curl);
    curl_slist_free_all(headers);
    curl_global_cleanup();
}

private string encode(string url)
{
    import std.algorithm: canFind;
    
    while(url.canFind("//"))
        url = url.replace("//", "/");
    
    url = url.replace("http:/", "http://");
    url = url.replace("https:/", "https://");
    
    return url;
}

private extern(C) size_t readResponse(ubyte* rbuffer, size_t size, size_t nmemb, void* udata)
{
    recvBuf.put(rbuffer[0 .. size * nmemb]);
    return size * nmemb;
}

private void request(string url, void delegate(ubyte[]) recv)
{
    recvBuf.clear();
    curl_easy_setopt(curl, CurlOption.url, url.toStringz);
    
    auto err = curl_easy_perform(curl);
    if(err != CurlError.ok) throw new Exception("cURL request failed: %s".format(curl_easy_strerror(err).fromStringz));
    
    recv(recvBuf[]);
}

void setAPIKey(string key)
{
    headers = curl_slist_append(headers, "X-EPU-Key: %s".format(key).toStringz);
    
    curl_easy_setopt(curl, CurlOption.httpheader, headers);
}

/++
    Downloads the file at url and saves it to destination.
+/
void download(string url, string destination)
{
    url = encode(url);
    
    info("Downloading ", url, " to ", destination);
    
    auto output = File(destination, "wb");
    request(url, (ubyte[] data) { output.rawWrite(data); } );
}

/++
    Retrieves the contents of the file at url and returns it as a string.
+/
string get(string url)
{
    url = encode(url);
    
    info("Fetching ", url);
    
    ubyte[] buffer;
    request(url,  (ubyte[] data) { buffer ~= data; } );
    
    return (cast(char[])buffer).idup;
}
