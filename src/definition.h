/******************************************************************************
 *
 * $Id$
 *
 * Copyright (C) 1997-1999 by Dimitri van Heesch.
 *
 * Permission to use, copy, modify, and distribute this software and its
 * documentation under the terms of the GNU General Public License is hereby 
 * granted. No representations are made about the suitability of this software 
 * for any purpose. It is provided "as is" without express or implied warranty.
 * See the GNU General Public License for more details.
 *
 * All output generated with Doxygen is not covered by this license.
 *
 */

#ifndef DEFINITION_H
#define DEFINITION_H

#include "qtbc.h"
#include <qlist.h>

class FileDef;
class OutputList;
class SectionList;

/*! The common base class of all definitions. */
class Definition
{
  public:
    /*! create a new definition */
    Definition(const char *name,const char *b=0,const char *d=0);
    /*! destroys the definition */
    virtual ~Definition();
    /*! returns the name of the definition */
    QCString name() const { return n; }
    /*! returns the base name of the output file that contains this 
     *  definition. 
     */
    virtual QCString getOutputFileBase() const = 0;
    /*! Returns the name of the source listing of this file. */
    QCString sourceName() const { return getOutputFileBase()+"-source"; }
    /*! returns the detailed description of this definition */
    QCString documentation() const { return doc; }
    /*! returns the brief description of this definition */
    QCString briefDescription() const { return brief; }
    /*! sets a new \a name for the definition */
    void setName(const char *name) { n=name; }
    /*! sets the documentation of this definition to \a d. */
    void setDocumentation(const char *d) 
      { 
        doc=((QCString)d).stripWhiteSpace();
      }
    /*! sets the brief description of this definition to \a b.
     *  A dot is added to the sentence if not available.
     */
    void setBriefDescription(const char *b);
    /*! returns TRUE iff the definition is documented */
    virtual bool hasDocumentation();
    virtual bool isLinkableInProject() = 0;
    virtual bool isLinkable() = 0;

    bool isReference() { return !ref.isEmpty(); }
    void setReference(const char *r) { ref=r; }
    QCString getReference() { return ref; }

    /*! returns the base file name that corresponds with the \a name of this 
     *  definition. This replaces a number of special characters in the
     *  name by string that are more suitable to use in file names.
     *  The function getOutputFileBase() also uses this function in most cases.
     *  \sa setName(),Definition()
     */
    QCString nameToFile(const char *name);

    /*! Add the list of anchors that mark the sections that are found in the 
     * documentation.
     */
    void addSectionsToDefinition(QList<QCString> *anchorList);

    void setBodySegment(int bls,int ble) 
    {
      startBodyLine=bls; 
      endBodyLine=ble; 
    }
    void setBodyDef(FileDef *fd)         { bodyDef=fd; }
    int getStartBodyLine() const         { return startBodyLine; }
    int getEndBodyLine() const           { return endBodyLine; }
    FileDef *getBodyDef()                { return bodyDef; }
    void writeSourceRef(OutputList &ol,const char *scopeName);

  protected:
    int      startBodyLine;   // line number of the start of the definition
    int      endBodyLine;     // line number of the end of the definition
    FileDef *bodyDef;         // file definition containing the function body

  private: 
    QCString n;     // name of the definition
    QCString brief; // brief description
    QCString doc;   // detailed description
    QCString ref;   // reference to external documentation
    SectionList *sectionList; // list of all sections
};

#endif