<?xml version="1.0"?>
<!-- SPDX-License-Identifier: CC0-1.0 -->
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:f="http://www.forester-notes.org"
  xmlns:exsl="http://exslt.org/common"
  exclude-result-prefixes="f exsl">
  <xsl:import href="core.xsl" />
  <xsl:import href="links.xsl" />
  <xsl:import href="metadata.xsl" />
  <xsl:output method="html" encoding="utf-8" indent="no" omit-xml-declaration="yes" />
  <xsl:param name="tree-xml" />

  <!-- Forester 6 renders HTML itself. Use its XML metadata to apply ASC's #95
       fix to the corresponding HTML headers without rewriting page bodies. -->
  <xsl:variable name="frontmatter-list">
    <xsl:apply-templates select="document($tree-xml)/f:tree" mode="headers" />
  </xsl:variable>
  <xsl:variable name="frontmatters" select="exsl:node-set($frontmatter-list)/f:frontmatter" />

  <xsl:template match="f:tree" mode="headers">
    <xsl:if test="not(@hidden-when-empty = 'true' and not(f:mainmatter/*) and not(normalize-space(f:mainmatter)))">
      <xsl:if test="not(@show-heading = 'false')">
        <xsl:copy-of select="f:frontmatter" />
      </xsl:if>
      <xsl:apply-templates select="f:mainmatter" mode="headers" />
      <xsl:if test="not(@root = 'true')">
        <xsl:apply-templates select="f:backmatter" mode="headers" />
      </xsl:if>
    </xsl:if>
  </xsl:template>

  <xsl:template match="*" mode="headers">
    <xsl:apply-templates select="*" mode="headers" />
  </xsl:template>

  <xsl:template match="/headers">
    <xsl:if test="count(header) != count($frontmatters)">
      <xsl:message terminate="yes">HTML and XML header counts differ: <xsl:value-of select="count(header)" /> / <xsl:value-of select="count($frontmatters)" />.</xsl:message>
    </xsl:if>
    <xsl:copy><xsl:apply-templates mode="html" /></xsl:copy>
  </xsl:template>

  <xsl:template match="@* | node()" mode="html">
    <xsl:copy><xsl:apply-templates select="@* | node()" mode="html" /></xsl:copy>
  </xsl:template>

  <xsl:template match="header/div[@class='metadata']/ul" mode="html">
    <xsl:variable name="index" select="count(../../preceding-sibling::header) + 1" />
    <xsl:variable name="frontmatter" select="$frontmatters[$index]" />
    <xsl:variable name="date-count" select="count($frontmatter/f:date)" />
    <xsl:variable name="local-dates" select="count($frontmatter/f:meta[@name='local-date'])" />
    <xsl:copy>
      <xsl:for-each select="node()">
        <xsl:choose>
          <xsl:when test="self::li and $local-dates > 0 and count(preceding-sibling::li) &lt; $date-count">
            <xsl:if test="not(preceding-sibling::li)">
              <xsl:apply-templates select="$frontmatter/f:date[position() > last() - $local-dates]" />
            </xsl:if>
          </xsl:when>
          <xsl:when test="self::li[address[@class='author']] and $frontmatter/f:meta[@name='local-author' or @name='local-contributor']">
            <xsl:apply-templates select="$frontmatter/f:authors" />
          </xsl:when>
          <xsl:when test="self::li[a[@class='orcid']]">
            <xsl:apply-templates select="$frontmatter/f:meta[@name='orcid']" />
          </xsl:when>
          <xsl:otherwise><xsl:apply-templates select="." mode="html" /></xsl:otherwise>
        </xsl:choose>
      </xsl:for-each>
      <xsl:apply-templates select="$frontmatter/f:meta[@name='github']" />
      <xsl:apply-templates select="$frontmatter/f:meta[@name='mastodon']" />
    </xsl:copy>
  </xsl:template>
</xsl:stylesheet>
