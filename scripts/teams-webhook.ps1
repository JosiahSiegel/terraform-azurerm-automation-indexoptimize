param (
    [Parameter(Mandatory = $true)]
    [string]$webhookUrl,

    [Parameter(Mandatory = $true)]
    [object]$webhookData
)

# Function to transform Azure common alert schema to Microsoft Teams format
function Convert-AzureAlertToTeamsMessage {
    param (
        [Parameter(Mandatory = $true)]
        [object]$WebhookData
    )

    # Extract the request body from the webhook data and preprocess it
    $requestBody = $WebhookData.RequestBody -replace '"searchQuery":".*?[^\\]",', '' -replace '\\\\', '\\' -replace '\\n', ' ' -replace '\\\"', '"' -replace '[\r\n]', '' -replace '\s+', ' ' | ConvertFrom-Json

    # Extract relevant information from the request body
    $essentials = $requestBody.data.essentials
    $alertContext = $requestBody.data.alertContext

    # Extract the _ResourceId for creating a link
    $resourceId = $alertContext.condition.allOf[0].dimensions | Where-Object { $_.name -eq "_ResourceId" } | Select-Object -ExpandProperty value
    $resourceLink = "https://portal.azure.com/#resource$resourceId"

    # Extract resource group name and resource name from the resource ID
    $resourceIdParts = $resourceId -split '/'
    $resourceGroupName = $resourceIdParts[4]
    $resourceName = $resourceIdParts[-1]
    $linkText = "$resourceGroupName - $resourceName"

    # Create the Microsoft Teams message card
    $teamsMessage = @{
        "@type"      = "MessageCard"
        "@context"   = "http://schema.org/extensions"
        "themeColor" = "0076D7"
        "summary"    = "Azure Alert"
        "sections"   = @(
            @{
                "activityTitle" = $essentials.alertRule
                "facts"         = @(
                    @{
                        "name"  = "Severity"
                        "value" = $essentials.severity
                    },
                    @{
                        "name"  = "Description"
                        "value" = $essentials.description
                    },
                    @{
                        "name"  = "Affected Resources"
                        "value" = "[$linkText]($resourceLink)"
                    },
                    @{
                        "name"  = "Condition"
                        "value" = $alertContext.condition.allOf.Count
                    },
                    @{
                        "name"  = "Timestamp"
                        "value" = $essentials.firedDateTime
                    }
                )
            },
            @{
                "activityTitle" = "Search Results"
                "text"          = "[View Search Results]($($alertContext.condition.allOf[0].linkToSearchResultsUI))"
            }
        )
    }

    # Convert the message to JSON
    $jsonMessage = $teamsMessage | ConvertTo-Json -Depth 100

    return $jsonMessage
}

# Call the function with the webhook data parameter
$teamsMessage = Convert-AzureAlertToTeamsMessage -WebhookData $webhookData
Write-Output $teamsMessage

$uri = $webhookUrl
$response = Invoke-RestMethod -Method post -ContentType 'Application/Json' -Body $teamsMessage -Uri $uri
$response
