package com.cloudwick.sync.jobs.fetcher

import akka.actor.{Props, ActorSystem}
import akka.pattern.ask
import akka.util.Timeout
import com.mongodb.MongoTimeoutException
import com.mongodb.casbah.Imports._
import com.typesafe.config.ConfigFactory
import com.typesafe.scalalogging.slf4j.Logger
import org.slf4j.LoggerFactory

import scala.concurrent.ExecutionContext.Implicits.global
import scala.concurrent.duration._

/**
 * Start the jobs fetcher
 * @author ashrith
 */
object Start extends App {
  val logger = Logger(LoggerFactory getLogger this.getClass)

  if (args.length != 3) {
    logger.error(s"Usage: ${this.getClass.getName} [dice|indeed] [hourly|daily|deep] [hadoop|spark|cassandra]")
    System.exit(1)
  }
  val apiType = args(0)
  val fetchType = args(1)
  val searchTerm = args(2)
  val config = ConfigFactory.load()
  val system = ActorSystem("JobProcessing")
  implicit val timeout = Timeout(5 minutes)


  def conn: MongoClient = {
    MongoClient(
      config.getString("sync.mongo.host"),
      config.getInt("sync.mongo.port")
    )
  }

  def checkConnection = {
    try {
      conn(config.getString("sync.mongo.db")).command("serverStatus")
    } catch {
      case ex: MongoTimeoutException =>
        logger.error("Failed connecting to MongoDB. Reason: " + ex.getMessage)
        System.exit(1)
    }
  }

  def processDice(fType: String, sTerm: String) = {
    checkConnection
    val actor = system.actorOf(
      Props(classOf[Master],
        conn(config.getString("sync.mongo.db")),
        config.getString("sync.api.dice.url"),
        sTerm,
        config.getInt(s"sync.api.dice.fetch.$fType.age"),
        config.getInt(s"sync.api.dice.fetch.$fType.depth"),
        config.getInt(s"sync.api.dice.fetch.$fType.sort"),
        "CON_CORP"),
      name="jobs")

    val future = actor ? Messages.Start

    future.map { result =>
      logger.info("Total number of jobs processed: " + result)
      system.shutdown()
    }
  }

  def processIndeed(fType: String) = {
    logger.warn("WARN: Not yet implemented")
    System.exit(1)
  }

  apiType match {
    case "dice" =>
      fetchType match {
        case "hourly" =>
          processDice("hourly", searchTerm)
        case "daily" =>
          processDice("daily", searchTerm)
        case "deep" =>
          processDice("deep", searchTerm)
        case _ =>
          logger.error("Unexpected argument")
          System.exit(1)
      }
    case "indeed" =>
      fetchType match {
        case "hourly" =>
          processIndeed("hourly")
        case "daily" =>
          processIndeed("daily")
        case "deep" =>
          processIndeed("deep")
        case _ =>
          logger.error("Unexpected argument")
          System.exit(1)
      }
    case _ =>
      logger.error("Error: Unexpected argument")
      System.exit(1)
  }
}
