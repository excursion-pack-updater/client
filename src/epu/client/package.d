module epu.client;

import std.string;

struct Config
{
    static string backendURL;
    static string packID;
    static string apiKey;
    
    static string buildURL(string path)
    {
        return "%s/pack/%s/%s".format(backendURL, packID, path);
    }
}

void loadConfig(string filename)
{
    import std.algorithm: map;
    import std.file;
    import std.stdio: File;
    import std.range;
    
    if(filename.exists)
        foreach(line; File(filename).byLine.map!(x => x.idup.strip))
        {
            if(line.empty)
                continue;
            
            string[] bits = line.split("=");
            string key = bits[0];
            string value = bits[1 .. $].join(" ");
            
            switch(key)
            {
                case "backendURL":
                    Config.backendURL = value;
                    
                    break;
                case "packID":
                    Config.packID = value;
                    
                    break;
                case "apiKey":
                    Config.apiKey = value;
                    
                    break;
                default:
                    throw new Exception("Unknown config key `%s`".format(key));
            }
        }
    else
    {
        filename.write(q"EOF
backendURL=https://example.com/
packID=0
apiKey=00000000000000000000000000000000
EOF"
        );
        
        throw new Exception("Created example config ini.");
    }
}
