# Lightwood

Lightwood is the ill-considered offspring of a MediaWiki bot and a Slack app.

## Installation

1. Create a slack app
2. Install lightwood
3. Create `lightwood.yaml` (see the example)
4. Create some instance commands in `Lightwood/Commands.pm`
5. Proxy lightwood through your webserver

## Package requirements
I think these are the only additional perl modules needed:
```
 JSON
 Net::HTTP
 Net::Server
 WWW::Form::UrlEncoded
 YAML::Tiny
```
In Ubuntu, if you don't want to get them from CPAN, you can install the with `apt` as well:
```
 apt-get install libjson-perl libnet-http-perl libnet-server-perl libwww-form-urlencoded-perl libyaml-tiny-perl
```

## Required permissions for the Slack App:
These may vary based on what's needed by instance command implementations, but the minimum required is:
```
    app_mentions:read :     View messages that directly mention @Lightwood in conversations that the app is in
    chat:write        :     Send messages as @Lightwood
    commands          :     Add shortcuts and/or slash commands that people can use
    users:read        :     View people in a workspace
```

## License

Lightwood is distributed under the terms of the GNU Public License, either
version 2.0, the text of which which is provided in the file called `COPYING`,
or (at your option) any later version.

Furthermore, the icon file `lightwood.png`, which is a crop of the illustration
_Wrayburn and Lightwood_ by Sol Eytinge, Jr. originally published by Ticknor and
Fields in the 1867 Diamond Edition of Charles Dickens's _Our Mutual Friend_, is
believed to be in the public domain world-wide due to the expiration of its
copyright.  Use of this image file is unrestricted and permitted for any purpose.
