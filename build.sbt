name := "Cloudwick Sync"

version := "1.0"

scalaVersion := "2.10.4"

resolvers += "Typesafe repository" at "http://repo.typesafe.com/typesafe/releases/"

libraryDependencies += "org.scalatest" %% "scalatest" % "1.9.1" % "test"

libraryDependencies += "org.scalamock" %% "scalamock-scalatest-support" % "3.2" % "test"

libraryDependencies +=  "org.scalaj" %% "scalaj-http" % "1.1.4"

libraryDependencies += "com.typesafe.play" %% "play-json" % "2.3.0"

libraryDependencies += "com.typesafe.akka" %% "akka-actor" % "2.3.9"

libraryDependencies += "org.mongodb" %% "casbah" % "2.8.0"

libraryDependencies += "joda-time" % "joda-time" % "2.7"

libraryDependencies += "com.typesafe" % "config" % "1.2.1"