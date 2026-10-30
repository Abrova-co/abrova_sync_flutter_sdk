allprojects {
    repositories {
        google()
        mavenCentral()
        // Abrova packages are published on Abrova Center.
        maven { url = uri("https://center.abrova.ir/api/packages/abrova/maven") }
        // Eclipse Paho (used by the native Android SDK)
        maven { url = uri("https://repo.eclipse.org/content/repositories/paho-releases/") }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
