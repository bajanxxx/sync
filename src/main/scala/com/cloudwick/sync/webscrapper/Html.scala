package com.cloudwick.sync.webscrapper

import java.net.{HttpURLConnection, URL}

import org.ccil.cowan.tagsoup.jaxp.SAXFactoryImpl
import org.xml.sax.InputSource

import scala.xml.Node
import scala.xml.parsing.NoBindingFactoryAdapter

/**
 * Wrapper class for getting the raw HTML and parse to XML
 * @author ashrith
 */
object Html {
  lazy val adapter = new NoBindingFactoryAdapter
  lazy val parser  = (new SAXFactoryImpl).newSAXParser

  /**
   * Loads a http page, parse's it and converts to structured XML
   * @param url http url page to load
   * @param headers additional headers to be passed to the http request
   * @return XML Node
   */
  def load(url: URL, headers: Map[String, String] = Map.empty): Node = {
    val conn = url.openConnection().asInstanceOf[HttpURLConnection]
    for ((k, v) <- headers)
      conn.setRequestProperty(k, v)
    val source = new InputSource(conn.getInputStream)
    adapter.loadXML(source, parser)
  }

}
