function Get-XmlNode {
    [CmdletBinding(DefaultParameterSetName = 'FromDocument')]
    param(
        # EITHER pass a whole XML document...
        [Parameter(ParameterSetName = 'FromDocument', Mandatory, Position = 0)]
        [xml] $Xml,

        # ...OR pass a node to use as the context.
        [Parameter(ParameterSetName = 'FromNode', Mandatory, Position = 0)]
        [System.Xml.XmlNode] $Node,

        [Parameter(Mandatory, Position = 1)]
        [string] $XPath
    )

    # Pick the context (document or node)
    $context = if ($PSCmdlet.ParameterSetName -eq 'FromNode') { $Node } else { $Xml }

    $result = $context.SelectSingleNode($XPath)

    if (-not $result) {
        throw "XML node not found: $XPath"
    }

    return $result
}
