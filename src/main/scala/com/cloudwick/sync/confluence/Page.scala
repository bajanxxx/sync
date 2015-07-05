package com.cloudwick.sync.confluence

/**
 * Confluence Page Wrapper
 */
case class Page(sKey: String, pTitle: String, pBody: String, ancestorId: Option[String] = None)