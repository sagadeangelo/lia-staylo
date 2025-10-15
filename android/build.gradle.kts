// android/build.gradle.kts — Project-level (seguro, sin redirecciones del build dir)

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Tarea clean estándar
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
