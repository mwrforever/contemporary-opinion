allprojects {
    repositories {
        google()
        mavenCentral()
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

// Force every Android library plugin (e.g. flutter_ringtone_player) to compile
// against at least SDK 34. Some plugins hard-pin compileSdk to 33 in their own
// build.gradle, overriding the version Flutter enforces. Their androidx
// dependencies (fragment 1.7.1, core-ktx 1.13.1, lifecycle 2.7.0, window 1.2.0,
// ...) require compileSdk >= 34, so a lower value fails :checkReleaseAarMetadata
// with 15 AAR metadata errors. Raising the minimum here fixes it for any plugin
// stuck on an old SDK, without waiting for an upstream release.
subprojects {
    afterEvaluate {
        extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.let { lib ->
            if ((lib.compileSdk ?: 0) < 34) {
                lib.compileSdk = 34
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
