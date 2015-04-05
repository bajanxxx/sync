package com.cloudwick.sync.jobs.fetcher

import akka.actor.{Props, ActorRef, Actor}
import akka.event.Logging
import akka.util.Timeout
import com.mongodb.casbah.Imports._
import play.api.libs.json.{Json, JsValue}
import akka.pattern.ask // to get the ? operator into scope

import scalaj.http.{Http, HttpResponse}
import scala.concurrent.duration._

/**
 * Parent Akka actor which kicks off other tasks and counts number of jobs processed by individual
 * actor.
 *
 * @author ashrith
 */
class Master(db: MongoDB,
             baseUrl: String,
             searchTerm: String,
             age: Int,
             depth: Int,
             sort: Int,
             grep: String) extends Actor {
  val log = Logging(context.system, this)
  val collection = db("jobs")

  private var running = false
  private var totalJobs = 0
  private var jobsProcessed = 0
  private val jobsToProcessRequested = depth * 50
  private var jobsToProcessRequired = 0
  private var initializer: Option[ActorRef] = None

  implicit val timeout = Timeout(5 minutes)

  override def preStart() = {
    log.debug("Starting ProcessRequest")
  }

  override def preRestart(reason: Throwable, message: Option[Any]): Unit = {
    log.error(reason, "Restarting due to [{}] when processing [{}]",
      reason.getMessage, message.getOrElse(""))
  }

  def totalJobsFetcher: Int = {
    val response: HttpResponse[String] = Http(baseUrl)
      .option(_.setInstanceFollowRedirects(true))
      .param("text", searchTerm)
      .param("age", age.toString)
      .asString
    val responseBody: JsValue = Json.parse(response.body)
    (responseBody \ "count").as[Int]
  }

  def receive = {
    case Messages.Start =>
      if (running) {
        log.warning("duplicate start message received")
      } else {
        running = true
        totalJobs = totalJobsFetcher
        if (jobsToProcessRequested > totalJobs) {
          jobsToProcessRequired = totalJobs
        } else {
          jobsToProcessRequired = jobsToProcessRequested
        }
        initializer = Some(sender()) // save the reference to process invoker
        (0 until depth) foreach { d =>
          val processor = context.actorOf(
            Props(
              classOf[ProcessBase],
              baseUrl,
              searchTerm,
              age,
              d + 1,
              sort,
              grep,
              collection
            ), name=s"m$d")
          processor ? Messages.ProcessPageRequest
        }
      }
    case Messages.Counter =>
      jobsProcessed += 1
      log.info("Total jobs: [{}]. Jobs to process: [{}] | Processed jobs: [{}]",
        totalJobs, jobsToProcessRequired, jobsProcessed)
      if (jobsToProcessRequired == jobsProcessed) {
        initializer.foreach(_ ! jobsProcessed)
      }
    case Messages.Stop =>
      log.warning("Exiting!")
    case x =>
      log.warning("Unrecognized message: [{}]", x)
  }
}