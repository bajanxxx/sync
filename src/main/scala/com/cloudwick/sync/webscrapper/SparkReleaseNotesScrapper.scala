package com.cloudwick.sync.webscrapper

import java.net.URL

import com.cloudwick.sync.confluence.{Page, Request}
import org.jsoup.Jsoup

import scala.collection.mutable.ArrayBuffer

/**
 * Scrapes, parses spark release notes and inserts into Confluence.
 */
object SparkReleaseNotesScrapper {
  private val parentUrl = "http://spark.apache.org/releases/"
  private val confluenceSpaceKey = "SPAR"
  private val confluenceParentPage = "Release Notes"

  def main(args: Array[String]) {
    val content = Html.load(new URL(parentUrl))
    val aTags = content \\ "a"

    var releases = ArrayBuffer[String]()
    val releaseUrls = ArrayBuffer[String]()

    val confluenceParentPageId = Request.getPageId(confluenceSpaceKey, confluenceParentPage)

    for (
      a <- aTags;
      href = a.attribute("href")
      if href.isDefined && href.get.toString().startsWith("spark-release")
    ) {
      releases += href.get.toString
    }

    releases.foreach { release =>
      releaseUrls += parentUrl + release
    }

    releaseUrls.foreach { releaseUrl =>
      val confluencePageName = releaseUrl.split("/").last.split("\\.").head.capitalize
      Request.getPageId(confluenceSpaceKey, confluencePageName) match {
        case Some(a) =>
          println(s"Page '$confluencePageName' already exists with id: $a")
        case None =>
          println(s"Page '$confluencePageName' does not exists")
          val document = Jsoup.connect(releaseUrl).get()
          val mainDiv = document.select("div.row > div").get(1)
          val body = mainDiv.html().replaceAll("(<br.*?>)", "<br/>").replaceAll("(\\r|\\n|\\r\\n)+", "")
          val page = Page("SPAR", confluencePageName, body, Request.getPageId("SPAR", "Release Notes"))
          Request.createPage(page)
      }
    }
  }
}
