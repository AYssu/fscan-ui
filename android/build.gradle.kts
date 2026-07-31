allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

subprojects {
    // 在项目评估前应用 Kotlin 插件，解决 jni 包兼容性问题
    pluginManager.withPlugin("com.android.library") {
        pluginManager.apply("org.jetbrains.kotlin.android")
    }

    // 强制所有子项目使用 compileSdk 36
    pluginManager.withPlugin("com.android.library") {
        afterEvaluate {
            if (extensions.findByType(com.android.build.gradle.LibraryExtension::class.java) != null) {
                extensions.configure<com.android.build.gradle.LibraryExtension> {
                    compileSdk = 36
                }
            }
        }
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
