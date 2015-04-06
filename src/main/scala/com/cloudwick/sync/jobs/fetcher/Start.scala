package com.cloudwick.sync.jobs.fetcher

import akka.actor.{Props, ActorSystem}
import akka.pattern.ask
import akka.util.Timeout
import com.mongodb.casbah.Imports._
import com.typesafe.config.ConfigFactory

import scala.concurrent.ExecutionContext.Implicits.global
import scala.concurrent.duration._

/**
 * Start the jobs fetcher
 * @author ashrith
 */
object Start extends App {
  val config = ConfigFactory.load()

  def conn: MongoClient = {
    MongoClient(
      config.getString("sync.mongo.host"),
      config.getInt("sync.mongo.port")
    )
  }

  val system = ActorSystem("JobProcessing")

  val actor = system.actorOf(
    Props(classOf[Master],
      conn(config.getString("sync.mongo.db")),
      config.getString("sync.api.dice.url"),
      "spark",
      config.getInt("sync.api.dice.fetch.daily.age"),
      config.getInt("sync.api.dice.fetch.daily.depth"),
      config.getInt("sync.api.dice.fetch.daily.sort"),
      "CON_CORP"),
    name="jobs")

  implicit val timeout = Timeout(5 minutes)

  val future = actor ? Messages.Start

  future.map { result =>
    println("Total number of jobs processed: " + result)
    system.shutdown()
  }
}
