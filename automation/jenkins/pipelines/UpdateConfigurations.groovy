static decodeBase64(Object params, String paramKey) {
    def text = params[paramKey]

    if (text != null && text != "") {
        return new String(text.decodeBase64(), "UTF-8")
    } else {
        throw new Exception("Missing '" + paramKey + "' parameter!")
    }
}

node {
    def baseJenkinsPath = "C:/jenkins/"
    def networkPath = "(?i)\\\\\\\\containers.domain.example.com\\\\jenkins\\\\"

    def address = decodeBase64(params, "Address")
    def siteName = "Default Web Site"
    def applicationName = decodeBase64(params, "ApplicationName")
    def applicationKey = decodeBase64(params, "ApplicationKey")
    def operationId = decodeBase64(params, "OperationId")
    def targetPath = decodeBase64(params, "TargetPath").replaceAll(networkPath, baseJenkinsPath)
    def resultPath = decodeBase64(params, "ResultPath").replaceAll(networkPath, baseJenkinsPath)
    def configPath = decodeBase64(params, "ConfigPath").replaceAll(networkPath, baseJenkinsPath)
    def subdomainsPath = baseJenkinsPath    + "subdomains/"
    def unzippedBundlesPath = baseJenkinsPath + "unzippedbundles/"
    def configsDoneFile = resultPath + "/" + applicationKey + "_" + operationId + ".configsdone"

    try {
        new File(configsDoneFile).write("{}")

        echo "Wrote '" + configsDoneFile + "'."
    } catch (Exception e1) {
        echo psScript

        def errorJson = "{\"Error\":{\"Message\": \"Jenkins - 'Apply Configurations' failed.\"}}"

        new File(configsDoneFile).write(errorJson)

        throw e1;
    }
}