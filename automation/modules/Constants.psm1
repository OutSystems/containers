# These values are not customizable.
# Changing these values will most likely break the automation process.

$global:UnifiedConfigFile = "App.Config"

$global:ArtefactsFolderName = "artefacts"

$global:ModulesFolderName = "modules"
$global:ConfigsFolderName = "configs"
$global:SecretsFolderName = "secrets"
$global:UnzippedBundlesFolderName = "unzippedbundles"

$global:ConfigsFolderInContainer = "c:\configs"
$global:SecretsFolderInContainer = "c:\secrets"

$global:PrepareDone = ".preparedone"
$global:DeployDone = ".deploydone"
$global:UndeployDone = ".undeploydone"
$global:ConfigsDone = ".configsdone"
