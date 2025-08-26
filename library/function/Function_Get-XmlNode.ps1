function Get-XmlNode {
    
    param(
        [xml]$Xml,
        [string]$XPath
    )

    $node = $Xml.SelectSingleNode($XPath)
    
    if (-not $node) {
        
        throw "XML node not found: $XPath"
    }
    
    return $node
}