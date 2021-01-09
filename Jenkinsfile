node('mac') {

    stage('Checkout/Build/Test') {

    // Checkout files.
    checkout([
        $class: 'GitSCM',
        branches: [[name: env.BRANCH_NAME]],
        doGenerateSubmoduleConfigurations: false,
        extensions: [], submoduleCfg: [],
        userRemoteConfigs: [[
            name: 'github',
            url: 'git@github.com:shaymanjohn/speccyMac.git'
        ]]
    ])

    // Build and Test
    sh 'xcodebuild -scheme "speccyMac" -configuration "Debug" build test -destination "platform=macOS,arch=x86_64" -enableCodeCoverage YES | /usr/local/bin/xcpretty -r junit'

    // Publish test restults.
    step([$class: 'JUnitResultArchiver', allowEmptyResults: true, testResults: 'build/reports/junit.xml'])
    }

    stage ('Notify') {
        // Send slack notification
        slackSend channel: '#build', message: 'speccyMac - build and test success.', teamDomain: 'karmatoad', token: 'swhGys1CY11kbCNtmypRvGL0'
    }
}
