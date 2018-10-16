static decodeBase64(Object params, String paramKey) {
    def text = params[paramKey]

    if (text != null && text != "") {
        return new String(text.decodeBase64(), "UTF-8")
    } else {
        throw new Exception("Missing '" + paramKey + "' parameter!")
    }
}

node {
    def psScript = ""

    def baseJenkinsPath = "C:/jenkins/"
    def networkPath = "(?i)\\\\\\\\containers.domain.example.com\\\\jenkins\\\\"

    def address = decodeBase64(params, "Address")
    def applicationName = decodeBase64(params, "ApplicationName")
    def applicationKey = decodeBase64(params, "ApplicationKey")
    def operationId = decodeBase64(params, "OperationId")
    def targetPath = decodeBase64(params, "TargetPath").replaceAll(networkPath, baseJenkinsPath)
    def resultPath = decodeBase64(params, "ResultPath").replaceAll(networkPath, baseJenkinsPath)
    def configPath = decodeBase64(params, "ConfigPath").replaceAll(networkPath, baseJenkinsPath)
    def secretsPath = baseJenkinsPath + "secrets/"
    def unzippedBundlesPath = baseJenkinsPath + "unzippedbundles/"

    try {
        psScript = """
        ${baseJenkinsPath}/pipelines/ContainerRemove.ps1    -SiteName "Default Web Site" `
                                                            -ApplicationKey "${applicationKey}" `
                                                            -OperationID "${operationId}" `
                                                            -BundlesFolder "${targetPath}" `
                                                            -SubdomainsFolder "" `
                                                            -UnzippedBundlesFolder "${unzippedBundlesPath}" `
                                                            -ConfigsFolder "${configPath}" `
                                                            -SecretsFolder "${secretsPath}" `
                                                            -ResultsFolder "${resultPath}"
        """

        def msg = powershell(returnStdout: true, script: psScript)
    } catch(Exception e1) {
        echo psScript

        def errorJson = "{\"Error\":{\"Message\": \"Jenkins - 'Container Undeploy' failed.\"}}"

        def filePath = resultPath + "/" + applicationKey + "_" + operationId

        new File(filePath + ".undeploydone").write(errorJson)

        throw e1;
    }
}