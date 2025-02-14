# utiliy function to manage flatpakref files
{ lib, ... }:
let
  # check if a value is a string
  isString = value: builtins.typeOf value == "string";

  # Check if a package declares a flatpakref
  isFlatpakref = { flatpakref ? null, ... }:
    flatpakref != null && isString flatpakref;

  # sanitize a URL to be used as a key in an attrset.
  sanitizeUrl = url: builtins.replaceStrings [ "https://" "/" "." ":" ] [ "https_" "_" "_" "_" ] url;

  # Create an origin name using the same algorithm as create_origin_remote_config()
  # from commons/flatpak-dir.c:
  #    - Extract the Name key from the ref file.
  #    - Split on '.' and get the last occurrence (prefix).
  #    - Lowercase the prefix.
  #    - Append the "-origin" suffix to the prefix.
  # If we fail to parse Name, then the key is invalid, and we fail hard.
  # See https://github.com/flatpak/flatpak/blob/b730771bd793b34fb63fcbf292beed35476e5b92/common/flatpak-dir.c#L14423
  createOriginRemoteConfig = name:
    let
      parts = builtins.filter (part: part != "") (lib.strings.splitString "." name);
      prefix = lib.strings.toLower (builtins.elemAt parts (builtins.length parts - 1));
      origin = ''${prefix}-origin'';
    in
    origin;

  # Extract the remote name from a package that declares a flatpakref:
  # 1. if the package sets an origin, use that as label for the remote url.
  # 2. if the package does not set an origin, use the remote name suggested by the flatpakref.
  # 3. if the package does not set an origin and the flatpakref does not suggest a remote name,
  #    sanitize Name.
  getRemoteNameFromFlatpakref = origin: cache:
    let
      remoteName = origin;
    in
    if remoteName == null
    then
      let
        flatpakrefdName =
          if builtins.hasAttr "SuggestRemoteName" cache
          then cache.SuggestRemoteName
          else createOriginRemoteConfig cache.Name; # Name is a mandatory field. If missing, fail hard.
      in
      flatpakrefdName
    else
      remoteName;

  # Fetch and convert an ini-like flatpakref file into an attrset, and cache it for future use
  # within the same activation.
  # We piggyback on builtins.fetchurl to fetch and cache flatpakref file. Pure nix evaluations
  # requrie a sha256 hash to be provided.
  # TODO: extract a generic ini-to-attrset function.
  flatpakrefToAttrSet = { flatpakref, sha256, ... }: cache:
    let
      updatedCache =
        if builtins.hasAttr (sanitizeUrl flatpakref) cache then
          cache
        else
          let
            fetchurlArgs =
              if sha256 != null
              then { url = flatpakref; sha256 = sha256; }
              else { url = flatpakref; };
            file = if lib.isPath flatpakref then flatpakref else builtins.fetchurl fetchurlArgs;
            iniContent = builtins.readFile file;
            lines = builtins.split "\r?\n" iniContent;
            parsed = builtins.filter (line: line != null) (map (line: builtins.match "(.*)=(.*)" (builtins.toString line)) lines);

            # Convert the list of key-value pairs into an attrset
            attrSet = builtins.listToAttrs (map (pair: { name = builtins.elemAt pair 0; value = builtins.elemAt pair 1; }) parsed);
          in
          cache // { ${(sanitizeUrl flatpakref)} = attrSet; };
    in
    updatedCache;
in
{
  inherit isFlatpakref sanitizeUrl flatpakrefToAttrSet getRemoteNameFromFlatpakref;
}
