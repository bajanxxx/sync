name := "cloudwick-sync"

version := "1.0"

scalaVersion := "2.11.7"

resolvers += "Typesafe repository" at "http://repo.typesafe.com/typesafe/releases/"

resolvers += "Sonatype OSS Snapshots" at "https://oss.sonatype.org/content/repositories/snapshots"

libraryDependencies +=  "org.scalaj" %% "scalaj-http" % "1.1.4"

libraryDependencies += "com.typesafe.play" %% "play-json" % "2.3.0"

libraryDependencies += "com.typesafe.akka" %% "akka-actor" % "2.3.9"

libraryDependencies += "org.mongodb" %% "casbah" % "2.8.0"

libraryDependencies += "joda-time" % "joda-time" % "2.7"

libraryDependencies += "com.typesafe" % "config" % "1.2.1"

libraryDependencies += "com.typesafe.scala-logging" %% "scala-logging-slf4j" % "2.1.2"

libraryDependencies += "org.slf4j" % "slf4j-simple" % "1.6.0"

libraryDependencies += "org.ccil.cowan.tagsoup" % "tagsoup" % "1.2.1"

libraryDependencies += "org.jsoup" % "jsoup" % "1.8.2"

libraryDependencies += "com.github.gilbertw1" %% "slack-scala-client" % "0.1.3"
