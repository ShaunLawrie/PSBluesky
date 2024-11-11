#requires -Modules @{ModuleName='PwshSpectreConsole'; ModuleVersion='2.1.2'}, @{ModuleName='PSBlueSky'; ModuleVersion='0.6.0'}

# REQUIRES WINDOWS TERMINAL PREVIEW 1.22+ FOR SIXEL https://devblogs.microsoft.com/commandline/windows-terminal-preview-1-22-release/
# Or another sixel capable terminal emulator but I've only tested on Windows Terminal Preview so far.
# This is super janky, I'm just having a play to get a feel for the API and it's also a chance to test out the new sixel support in Windows Terminal Preview and work out the visual bugs.

$ErrorActionPreference = "Stop"

if ($null -eq $global:BlueSkyAuthorCache) {
  $global:BlueSkyAuthorCache = @{}
}

# REQUIRES BLUE SKY CREDS TO BE SETUP
. $PSScriptRoot\functions\helpers.ps1
$timeline = Get-BskyTimelineThreaded -Limit 35

function Format-Post {
  param (
    [string] $Uri,
    [string] $Text,
    [string[]] $Images,
    [string] $AuthorHandle,
    [int] $Likes,
    [string] $Date,
    [string] $Color = 'DeepSkyBlue3_1'
  )

  # Cache author profiles
  if (-not $global:BlueSkyAuthorCache.ContainsKey($AuthorHandle)) {
    $global:BlueSkyAuthorCache[$AuthorHandle] = Get-BskyProfile $AuthorHandle
  }
  $author = $global:BlueSkyAuthorCache[$AuthorHandle]

  if ($Uri -match '^at://.*') {
    $Uri = _convertAT $Uri
  }

  # Format some chunks of text
  $avatarWidth = 10
  try {
    $authorImage = Get-SpectreSixelImage $author.Avatar -MaxWidth $avatarWidth
  } catch {
    $authorImage = Write-SpectreHost "[yellow]WARNING: Failed to load image[/]" -PassThru
  }
  $likesFormat = ":red_heart:  [red]$($Likes)[/]"
  $authorDisplayName = "[white]$($author.Display.Trim())[/]"
  $authorLink = "[grey69 link=$($Uri)]@$($AuthorHandle)[/]"
  $postDate = "[grey42]$($Date)[/]"
 
  $postData = @()

  if ($Text) {
    $postData += Write-SpectreHost "" -PassThru
    $postData += $Text
  }
  if ($Images) {
    $postData += Write-SpectreHost "" -PassThru
    try {
      if ($Images.Count -le 1) {
        $postData += Get-SpectreSixelImage $Images[0] -MaxWidth 50
      } else {
        $postData += $Images | ForEach-Object { Get-SpectreSixelImage $_ -MaxWidth 20 | Format-SpectrePadded -Top 0 -Bottom 1 -Left 0 -Right 0 } | Format-SpectreColumns
      }
    } catch {
      $postData += "Failed to load image: $_"
    }
  }
  $postData += Write-SpectreHost "" -PassThru

  $formattedPost = New-SpectreGridRow -Data @(
    ($authorImage | Format-SpectrePanel -Width $avatarWidth -Border None | Format-SpectrePadded -Top 1 -Bottom 0 -Left 0 -Right 0),
    ($postData | Format-SpectreRows)
  ) | Format-SpectreGrid -Padding 1

  $panelHeight = [Math]::Min($Host.UI.RawUI.WindowSize.Height, [Math]::Max(9, ($formattedPost | Format-SpectrePanel | Get-SpectreRenderableSize).Height))

  return $formattedPost | Format-SpectrePanel -Title "[white] $likesFormat $authorDisplayName $authorLink $postDate [/]" -Color $Color -Height $panelHeight -Expand
}

# Build the timeline
$formattedPosts = @()
foreach ($post in $timeline) {

  $formattedData = Format-Post -Uri $post.URL -Text $post.Text -Images $post.Images -AuthorHandle $post.Author -Likes $post.Liked -Date $post.Date

  if ($post.Reply) {
    # If this post is a reply, format the parent post and add it as a child to make it look threaded
    $children = @()
    
    if ($post.Reply.parent.uri -ne $post.Reply.root.uri) {
      $parentImages = _getEmbedThumbnails $post.Reply.parent.embed
      $children += @{
        Value = Format-Post -Uri $post.Reply.parent.uri -Text $post.Reply.parent.record.text -Images $parentImages -AuthorHandle $post.Reply.parent.author.handle -Likes $post.Reply.parent.likeCount -Date $post.Reply.parent.record.createdAt.ToLocalTime() -Color Grey30
        Children = @(
          @{
            Value = $formattedData
          }
        )
      }
    } else {
      $children += @{
        Value = $formattedData
      }
    }

    $rootImages = _getEmbedThumbnails $post.Reply.root.embed

    $formattedPosts += @{
      Value = Format-Post -Uri $post.Reply.root.uri -Text $post.Reply.root.record.text -Images $rootImages -AuthorHandle $post.Reply.root.author.handle -Likes $post.Reply.root.likeCount -Date $post.Reply.root.record.createdAt.ToLocalTime() -Color Grey30
      Children = @($children)
    } | Format-SpectreTree -Guide Line -Color Grey30
  } else {
    # Just add the post to the timeline
    $formattedPosts += $formattedData
  }
}

# Display the timeline
$formattedPosts | Out-SpectreHost