import com.android.build.api.dsl.LibraryExtension
import com.android.build.api.variant.LibraryAndroidComponentsExtension
import org.gradle.api.Action
import org.gradle.api.JavaVersion
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

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

subprojects {
    plugins.withId("com.android.library") {
        extensions.getByType(LibraryAndroidComponentsExtension::class.java).finalizeDsl(
            object : Action<LibraryExtension> {
                override fun execute(lib: LibraryExtension) {
                    lib.compileOptions {
                        sourceCompatibility = JavaVersion.VERSION_17
                        targetCompatibility = JavaVersion.VERSION_17
                    }
                }
            },
        )
    }
    // Bazı eklentiler (ör. workmanager_android) kendi build.gradle'ında jvmTarget'ı 1.8'e çeker;
    // değerlendirme sonrası kaydedilen bu ayar onlarınkinden sonra çalışıp Java 17 ile eşitler.
    val forceKotlinJvm17 = {
        tasks.withType<KotlinCompile>().configureEach {
            compilerOptions.jvmTarget.set(JvmTarget.JVM_17)
        }
    }
    if (state.executed) forceKotlinJvm17() else afterEvaluate { forceKotlinJvm17() }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
