/******************************************************************************
 *
 * 
 *
 * Copyright (C) 1997-2000 by Dimitri van Heesch.
 *
 * Permission to use, copy, modify, and distribute this software and its
 * documentation under the terms of the GNU General Public License is hereby 
 * granted. No representations are made about the suitability of this software 
 * for any purpose. It is provided "as is" without express or implied warranty.
 * See the GNU General Public License for more details.
 *
 */

%{

/*
 *	includes
 */
#include <stdio.h>
#include <stdlib.h>
#include <iostream.h>
#include <assert.h>
#include <ctype.h>

#include <qfileinfo.h>
#include <qdir.h>
#include <qtextstream.h>
#include <qregexp.h>
#include <qstack.h>
  
#include "config.h"
#include "version.h"
  
#ifdef DOXYWIZARD  
#include <stdarg.h>
void err(const char *fmt, ...)
{
  va_list args;
  va_start(args, fmt);
  vfprintf(stderr, fmt, args);
  va_end(args); 
}
void warn_cont(const char *fmt, ...)
{
  va_list args;
  va_start(args, fmt);
  vfprintf(stderr, fmt, args);
  va_end(args);
}
void initWarningFormat()
{
}
#else
#include "doxygen.h"
#include "message.h"
#include "pre.h"
#include "version.h"
#include "language.h"
#endif

#define MAX_INCLUDE_DEPTH 10
#define YY_NEVER_INTERACTIVE 1
#define YY_NO_UNPUT
  
/* -----------------------------------------------------------------
 *
 *	exported variables
 */
  
#CONFIG Config

/* -----------------------------------------------------------------
 *
 *	static variables
 */

struct ConfigFileState
{
  int lineNr;
  FILE *filePtr;
  YY_BUFFER_STATE oldState;
  YY_BUFFER_STATE newState;
  QCString fileName;
};  

static const char       *inputString;
static int	         inputPosition;
static int               yyLineNr;
static QCString          yyFileName;
static QCString          tmpString;
static QCString         *s=0;
static bool             *b=0;
static QStrList         *l=0;
static int               lastState;
static QCString          elemStr;
static QCString          includeName;
static QStrList          includePathList;
static QStack<ConfigFileState> includeStack;  
static int               includeDepth;

#CONFIG Static

/* -----------------------------------------------------------------
 */
#undef	YY_INPUT
#define	YY_INPUT(buf,result,max_size) result=yyread(buf,max_size);

static int yyread(char *buf,int max_size)
{
    // no file included
    if (includeStack.isEmpty()) 
    {
        int c=0;
	while( c < max_size && inputString[inputPosition] )
	{
	      *buf = inputString[inputPosition++] ;
	      c++; buf++;
  	}
	return c;
    } 
    else 
    {
        //assert(includeStack.current()->newState==YY_CURRENT_BUFFER);
	return fread(buf,1,max_size,includeStack.current()->filePtr);
    }
}


static FILE *tryPath(const char *path,const char *fileName)
{
  QCString absName=(QCString)path+"/"+fileName;
  QFileInfo fi(absName);
  if (fi.exists() && fi.isFile())
  {
    FILE *f=fopen(absName,"r");
    if (!f) err("Error: could not open file %s for reading\n",absName.data());
    return f;
  }
  return 0;
}

static FILE *findFile(const char *fileName)
{
  char *s=includePathList.first();
  while (s) // try each of the include paths
  {
    FILE *f = tryPath(s,fileName);
    if (f) return f;
    s=includePathList.next();
  } 
  // try cwd if includePathList fails
  return tryPath(".",fileName);
}

static void readIncludeFile(const char *incName)
{
  if (includeDepth==MAX_INCLUDE_DEPTH) {
    err("Error: maximum include depth (%d) reached, %s is not included. Aborting...\n",
	MAX_INCLUDE_DEPTH,incName);
    exit(1);
  } 

  QCString inc = incName;
  inc = inc.stripWhiteSpace();
  uint incLen = inc.length();
  if (inc.at(0)=='"' && inc.at(incLen-1)=='"') // strip quotes
  {
    inc=inc.mid(1,incLen-2);
  }

  FILE *f;

  //printf("Searching for `%s'\n",incFileName.data());
  if ((f=findFile(inc))) // see if the include file can be found
  {
    // For debugging
#if SHOW_INCLUDES
    for (i=0;i<includeStack.count();i++) msg("  ");
    msg("@INCLUDE = %s: parsing...\n",inc.data());
#endif

    // store the state of the old file 
    ConfigFileState *fs=new ConfigFileState;
    fs->oldState=YY_CURRENT_BUFFER;
    fs->lineNr=yyLineNr;
    fs->fileName=yyFileName;
    fs->filePtr=f;
    // push the state on the stack
    includeStack.push(fs);
    // set the scanner to the include file
    yy_switch_to_buffer(yy_create_buffer(f, YY_BUF_SIZE));
    fs->newState=YY_CURRENT_BUFFER;
    yyFileName=inc;
    includeDepth++;
  } 
  else
  {
    err("Error: @INCLUDE = %s: not found!\n",inc.data());
    exit(1);
  }
}


%}

%option noyywrap

%x      Start
%x	SkipComment
%x      GetString
%x      GetBool
%x      GetStrList
%x      GetQuotedString
%x      GetEnvVar
%x      Include

%%

<*>\0x0d
<Start,GetString,GetStrList,GetBool>"#"	{ BEGIN(SkipComment); }
#CONFIG Rules

<Start>"@INCLUDE_PATH"[ \t]*"=" 	{ BEGIN(GetStrList); l=&includePathList; l->clear(); elemStr=""; }
  /* include a config file */
<Start>"@INCLUDE"[ \t]*"="     		{ BEGIN(Include);}
<Include>([^ \"\t\r\n]+)|("\""[^\n\"]+"\"") { 
  					  readIncludeFile(yytext); 
  					  BEGIN(Start);
					}
<<EOF>>					{
                                          //printf("End of include file\n");
					  //printf("Include stack depth=%d\n",g_includeStack.count());
                                          if (includeStack.isEmpty())
					  {
					    //printf("Terminating scanner!\n");
					    yyterminate();
					  }
					  else
					  {
					    ConfigFileState *fs=includeStack.pop();
					    fclose(fs->filePtr);
					    YY_BUFFER_STATE oldBuf = YY_CURRENT_BUFFER;
					    yy_switch_to_buffer( fs->oldState );
					    yy_delete_buffer( oldBuf );
					    yyLineNr=fs->lineNr;
					    yyFileName=fs->fileName;
					    delete fs; fs=0;
                                            includeDepth--;
					  }
  					}

<Start>[a-z_A-Z0-9]+			{ err("Warning: ignoring unknown tag `%s' at line %d, file %s\n",yytext,yyLineNr,yyFileName.data()); }
<GetString,GetBool>\n			{ yyLineNr++; BEGIN(Start); }
<GetStrList>\n				{ 
  					  yyLineNr++; 
					  if (!elemStr.isEmpty())
					  {
					    //printf("elemStr1=`%s'\n",elemStr.data());
					    l->append(elemStr);
					  }
					  BEGIN(Start); 
					}
<GetStrList>[ \t]+			{
  				          if (!elemStr.isEmpty())
					  {
					    //printf("elemStr2=`%s'\n",elemStr.data());
  					    l->append(elemStr);
					  }
					  elemStr.resize(0);
  					}
<GetString>[^ \"\t\r\n]+		{ (*s)+=yytext; }
<GetString,GetStrList>"\""		{ lastState=YY_START;
  					  BEGIN(GetQuotedString); 
                                          tmpString.resize(0); 
					}
<GetQuotedString>"\""|"\n" 		{ 
  					  //printf("Quoted String = `%s'\n",tmpString.data());
  					  if (lastState==GetString)
					    (*s)+=tmpString;
					  else
					    elemStr+=tmpString;
					  if (*yytext=='\n')
					  {
					    err("Warning: Missing end quote (\") on line %d, file %s\n",yyLineNr,yyFileName.data());
					    yyLineNr++;
					  }
					  BEGIN(lastState);
  					}
<GetQuotedString>"\\\""			{
  					  tmpString+='"';
  					}
<GetQuotedString>.			{ tmpString+=*yytext; }
<GetBool>[a-zA-Z]+			{ 
  					  QCString bs=yytext; 
  					  bs=bs.upper();
  					  if (bs=="YES")
					    *b=TRUE;
					  else if (bs=="NO")
					    *b=FALSE;
					  else 
					  {
					    *b=FALSE; 
					    warn_cont("Warning: Invalid value `%s' for "
						 "boolean tag in line %d, file %s; use YES or NO\n",
						 bs.data(),yyLineNr,yyFileName.data());
					  }
					}
<GetStrList>[^ \#\"\t\r\n]+		{
  					  elemStr+=yytext;
  					}
<SkipComment>\n				{ yyLineNr++; BEGIN(Start); }
<SkipComment>\\[ \r\t]*\n		{ yyLineNr++; BEGIN(Start); }
<*>\\[ \r\t]*\n				{ yyLineNr++; }
<*>.					
<*>\n					{ yyLineNr++ ; }

%%

/*@ ----------------------------------------------------------------------------
 */


void dumpConfig()
{
#CONFIG Dump
}

void Config::init()
{
#CONFIG Init
}

static void writeBoolValue(QTextStream &t,bool v)
{
  if (v) t << "YES"; else t << "NO";
}

static void writeIntValue(QTextStream &t,int i)
{
  t << i;
}

static void writeStringValue(QTextStream &t,QCString &s)
{
  const char *p=s.data();
  char c;
  bool hasBlanks=FALSE;
  if (p)
  {
    while ((c=*p++)!=0 && !hasBlanks) hasBlanks = (c==' ' || c=='\n' || c=='\t');
    if (hasBlanks) 
      t << "\"" << s << "\"";
    else
      t << s;
  }
}

static void writeStringList(QTextStream &t,QStrList &l)
{
  const char *p = l.first();
  bool first=TRUE;
  while (p)
  {
    char c;
    const char *s=p;
    bool hasBlanks=FALSE;
    while ((c=*p++)!=0 && !hasBlanks) hasBlanks = (c==' ' || c=='\n' || c=='\t');
    if (!first) t << "                         ";
    first=FALSE;
    if (hasBlanks) t << "\"" << s << "\""; else t << s;
    p = l.next();
    if (p) t << " \\" << endl;
  }
}

void writeTemplateConfig(QFile *f,bool sl)
{
  QTextStream t(f);
#ifdef DOXYWIZARD
  t << "# Doxygen configuration generated by Doxywizard version " << versionString << endl;
#else
  t << "# Doxyfile " << versionString << endl << endl;
#endif
  if (!sl)
  {
    t << "# This file describes the settings to be used by doxygen for a project\n";
    t << "#\n";
    t << "# All text after a hash (#) is considered a comment and will be ignored\n";
    t << "# The format is:\n";
    t << "#       TAG = value [value, ...]\n";
    t << "# For lists items can also be appended using:\n";
    t << "#       TAG += value [value, ...]\n";
    t << "# Values that contain spaces should be placed between quotes (\" \")\n";
  }
#CONFIG Template
}

void configStrToVal()
{
  if (tabSizeString.isEmpty())
  {
    Config::tabSize=8;
  }
  else
  {
    bool ok;
    int ts = tabSizeString.toInt(&ok);
    if (!ok || ts<1 || ts>16)
    {
      warn_cont("Warning: argument of TAB_SIZE is not a valid number, using tab size of 8 spaces!\n");
      ts=8;
    }
    Config::tabSize = ts;
  }
  
  if (colsInAlphaIndexString.isEmpty())
  {
    Config::colsInAlphaIndex=5;
  }
  else
  {
    bool ok;
    int cols = colsInAlphaIndexString.toInt(&ok);
    if (!ok || cols<1 || cols>20)
    {
      warn_cont("Warning: argument of COLS_IN_ALPHA_INDEX is not a valid number in the range [1..20]!\n"
	   "Using the default of 5 columns!\n");
      cols = 5;
    }
    Config::colsInAlphaIndex=cols;
  }
  
  if (maxDotGraphWidthString.isEmpty())
  {
    Config::maxDotGraphWidth=1024;
  }
  else
  {
    bool ok;
    int width =maxDotGraphWidthString.toInt(&ok);
    if (!ok)
    {
      warn_cont("Warning: argument of MAX_DOT_GRAPH_WIDTH is not a valid number in the range [1..20]!\n"
	   "Using the default of 1024 pixels!\n");
      width=1024;
    }
    else if (width<100) // clip to lower bound
    {
      width=100;
    }
    else if (width>30000) // clip to upper bound
    {
      width=30000;
    }
    Config::maxDotGraphWidth=width;
  }

  if (maxDotGraphHeightString.isEmpty())
  {
    Config::maxDotGraphHeight=1024;
  }
  else
  {
    bool ok;
    int height =maxDotGraphHeightString.toInt(&ok);
    if (!ok)
    {
      warn_cont("Warning: argument of MAX_DOT_GRAPH_WIDTH is not a valid number in the range [1..20]!\n"
	   "Using the default of 1024 pixels!\n");
      height=1024;
    }
    else if (height<100) // clip to lower bound
    {
      height=100;
    }
    else if (height>30000) // clip to upper bound
    {
      height=30000;
    }
    Config::maxDotGraphHeight=height;
  }
}

static void substEnvVarsInString(QCString &s)
{
  static QRegExp re("\\$\\([a-z_A-Z0-9]+\\)");
  if (s.isEmpty()) return;
  int p=0;
  int i,l;
  //printf("substEnvVarInString(%s) start\n",s.data());
  while ((i=re.match(s,p,&l))!=-1)
  {
    //printf("Found environment var s.mid(%d,%d)=`%s'\n",i+2,l-3,s.mid(i+2,l-3).data());
    QCString env=getenv(s.mid(i+2,l-3));
    substEnvVarsInString(env); // recursively expand variables if needed.
    s = s.left(i)+env+s.right(s.length()-i-l);
    p=i+env.length(); // next time start at the end of the expanded string
  }
  //printf("substEnvVarInString(%s) end\n",s.data());
}

static void substEnvVarsInStrList(QStrList &sl)
{
  char *s = sl.first();
  while (s)
  {
    QCString result(s);
    bool wasQuoted = (result.find(' ')!=-1) || (result.find('\t')!=-1);
    substEnvVarsInString(result);

    if (!wasQuoted) /* as a result of the expansion, a single string
		       may have expanded into a list, which we'll
		       add to sl. If the orginal string already 
		       contained multiple elements no further 
		       splitting is done to allow quoted items with spaces! */
    {



      int l=result.length();
      int i,p=0;
      // skip spaces
      // search for a "word"
      for (i=0;i<l;i++)
      {
	char c;
	// skip until start of new word
	while (i<l && ((c=result.at(i))==' ' || c=='\t')) i++; 
	p=i; // p marks the start index of the word
	// skip until end of a word
	while (i<l && ((c=result.at(i))!=' ' && c!='\t' && c!='"')) i++;
	if (i<l) // not at the end of the string
	{
	  if (c=='"') // word within quotes
	  {
	    p=i+1;
	    for (i++;i<l;i++)
	    {
	      c=result.at(i);
	      if (c=='"') // end quote
	      {
		// replace the string in the list and go to the next item.
		sl.insert(sl.at(),result.mid(p,i-p)); // insert new item before current item.
		sl.next();                 // current item is now the old item
		p=i+1;
		break; 
	      }
	      else if (c=='\\') // skip escaped stuff
	      {
		i++;
	      }
	    }
	  }
	  else if (c==' ' || c=='\t') // separator
	  {
	    // replace the string in the list and go to the next item.
	    sl.insert(sl.at(),result.mid(p,i-p)); // insert new item before current item.
	    sl.next();                 // current item is now the old item
	    p=i+1;
	  }
	}
      }
      if (p!=l) // add the leftover as a string
      {
	// replace the string in the list and go to the next item.
	sl.insert(sl.at(),result.right(l-p)); // insert new item before current item.
	sl.next();                 // current item is now the old item
      }

      // remove the old unexpanded string from the list
      i=sl.at();
      sl.remove(); // current item index changes if the last element is removed.
      if (sl.at()==i)     // not last item
	s = sl.current();
      else                // just removed last item
	s = 0;
    }
    else // just goto the next element in the list
    {
      s=sl.next();
    }
  }
}


void substituteEnvironmentVars()
{
#CONFIG Substenv
}

void checkConfig()
{
  //if (!projectName.isEmpty())
  //{
  //  projectName[0]=toupper(projectName[0]);
  //}

  if (Config::warnFormat.isEmpty())
  {
    Config::warnFormat="$file:$line $text";
  }
  else
  {
    if (Config::warnFormat.find("$file")==-1)
    {
      err("Error: warning format does not contain a $file tag!\n");
      exit(1);
    }
    if (Config::warnFormat.find("$line")==-1)
    {
      err("Error: warning format does not contain a $line tag!\n");
      exit(1);
    }
    if (Config::warnFormat.find("$text")==-1)
    {
      err("Error: wanring format foes not contain a $text tag!\n");
      exit(1);
    }
  }
  initWarningFormat();

  // set default man page extension if non is given by the user
  if (Config::manExtension.isEmpty())
  {
    Config::manExtension=".3";
  }
  
  Config::paperType = Config::paperType.lower().stripWhiteSpace(); 
  if (Config::paperType.isEmpty())
  {
    Config::paperType = "a4wide";
  }
  if (Config::paperType!="a4" && Config::paperType!="a4wide" && Config::paperType!="letter" && 
      Config::paperType!="legal" && Config::paperType!="executive")
  {
    err("Error: Unknown page type specified");
  }
  
  Config::outputLanguage=Config::outputLanguage.stripWhiteSpace();
  if (Config::outputLanguage.isEmpty())
  {
    Config::outputLanguage = "English";
#ifndef DOXYWIZARD
    setTranslator("English");
#endif
  }
  else
  {
#ifndef DOXYWIZARD
    if (!setTranslator(Config::outputLanguage))
    {
      err("Error: Output language %s not supported! Using English instead.\n",
	  Config::outputLanguage.data());
    }
#endif
  }
  
  // Test to see if output directory is valid
  if (Config::outputDir.isEmpty()) 
    Config::outputDir=QDir::currentDirPath();
  else
  {
    QDir dir(Config::outputDir);
    if (!dir.exists())
    {
      dir.setPath(QDir::currentDirPath());
      if (!dir.mkdir(Config::outputDir))
      {
        err("Error: tag OUTPUT_DIRECTORY: Output directory `%s' does not "
	    "exist and cannot be created\n",Config::outputDir.data());
        exit(1);
      }
      else if (!Config::quietFlag)
      {
	err("Notice: Output directory `%s' does not exist. "
	    "I have created it for you.\n", Config::outputDir.data());
      }
      dir.cd(Config::outputDir);
    }
    Config::outputDir=dir.absPath();
  }

  if (Config::htmlOutputDir.isEmpty() && Config::generateHtml)
  {
    Config::htmlOutputDir=Config::outputDir+"/html";
  }
  else if (Config::htmlOutputDir && Config::htmlOutputDir[0]!='/')
  {
    Config::htmlOutputDir.prepend(Config::outputDir+'/');
  }
  QDir htmlDir(Config::htmlOutputDir);
  if (Config::generateHtml && !htmlDir.exists() && 
      !htmlDir.mkdir(Config::htmlOutputDir))
  {
    err("Could not create output directory %s\n",Config::htmlOutputDir.data());
    exit(1);
  }
  
  if (Config::latexOutputDir.isEmpty() && Config::generateLatex)
  {
    Config::latexOutputDir=Config::outputDir+"/latex";
  }
  else if (Config::latexOutputDir && Config::latexOutputDir[0]!='/')
  {
    Config::latexOutputDir.prepend(Config::outputDir+'/');
  }
  QDir latexDir(Config::latexOutputDir);
  if (Config::generateLatex && !latexDir.exists() && 
      !latexDir.mkdir(Config::latexOutputDir))
  {
    err("Could not create output directory %s\n",Config::latexOutputDir.data());
    exit(1);
  }
  
  if (Config::rtfOutputDir.isEmpty() && Config::generateRTF)
  {
    Config::rtfOutputDir=Config::outputDir+"/rtf";
  }
  else if (Config::rtfOutputDir && Config::rtfOutputDir[0]!='/')
  {
    Config::rtfOutputDir.prepend(Config::outputDir+'/');
  }
  QDir rtfDir(Config::rtfOutputDir);
  if (Config::generateRTF && !rtfDir.exists() && 
      !rtfDir.mkdir(Config::rtfOutputDir))
  {
    err("Could not create output directory %s\n",Config::rtfOutputDir.data());
    exit(1);
  }

  if (Config::manOutputDir.isEmpty() && Config::generateMan)
  {
    Config::manOutputDir=Config::outputDir+"/man";
  }
  else if (Config::manOutputDir && Config::manOutputDir[0]!='/')
  {
    Config::manOutputDir.prepend(Config::outputDir+'/');
  }
  QDir manDir(Config::manOutputDir);
  if (Config::generateMan && !manDir.exists() && 
      !manDir.mkdir(Config::manOutputDir))
  {
    err("Could not create output directory %s\n",Config::manOutputDir.data());
    exit(1);
  }

  // expand the relative stripFromPath values
  char *sfp = Config::stripFromPath.first();
  while (sfp)
  {
    QCString path = sfp;
    if (path.at(0)!='/' && (path.length()<=2 || path.at(1)!=':'))
    {
      QFileInfo fi(path);
      if (fi.exists() && fi.isDir())
      {
	int i = Config::stripFromPath.at();
	Config::stripFromPath.remove();
	if (Config::stripFromPath.at()==i) // did not remove last item
	  Config::stripFromPath.insert(i,fi.absFilePath()+"/");
	else
	  Config::stripFromPath.append(fi.absFilePath()+"/");
      }
    }
    sfp = Config::stripFromPath.next();
  }
  
  
  // Test to see if HTML header is valid
  if (!Config::headerFile.isEmpty())
  {
    QFileInfo fi(Config::headerFile);
    if (!fi.exists())
    {
      err("Error: tag HTML_HEADER: header file `%s' "
	  "does not exist\n",Config::headerFile.data());
      exit(1);
    }
  }
  // Test to see if HTML footer is valid
  if (!Config::footerFile.isEmpty())
  {
    QFileInfo fi(Config::footerFile);
    if (!fi.exists())
    {
      err("Error: tag HTML_FOOTER: footer file `%s' "
	  "does not exist\n",Config::footerFile.data());
      exit(1);
    }
  }
  // Test to see if LaTeX header is valid
  if (!Config::latexHeaderFile.isEmpty())
  {
    QFileInfo fi(Config::latexHeaderFile);
    if (!fi.exists())
    {
      err("Error: tag LATEX_HEADER: header file `%s' "
	  "does not exist\n",Config::latexHeaderFile.data());
      exit(1);
    }
  }
  // check include path
  char *s=Config::includePath.first();
  while (s)
  {
    QFileInfo fi(s);
    if (!fi.exists()) err("Warning: tag INCLUDE_PATH: include path `%s' "
	                  "does not exist\n",s);
#ifndef DOXYWIZARD
    addSearchDir(fi.absFilePath());
#endif
    s=Config::includePath.next();
  }

  // check aliases
  s=Config::aliasList.first();
  while (s)
  {
    QRegExp re("[a-z_A-Z][a-z_A-Z0-9]*[ \t]*=");
    QCString alias=s;
    alias=alias.stripWhiteSpace();
    if (alias.find(re)!=0)
    {
      err("Illegal alias format `%s'. Use \"name=value\"\n",alias.data());
    }
    s=Config::aliasList.next();
  }
  
  // check dot path
  if (!Config::dotPath.isEmpty())
  {
    if (Config::dotPath.find('\\')!=-1)
    {
      if (Config::dotPath.at(Config::dotPath.length()-1)!='\\')
      {
	Config::dotPath+='\\';
      } 
    } 
    else if (Config::dotPath.find('/')!=-1)
    {
      if (Config::dotPath.at(Config::dotPath.length()-1)!='/')
      {
	Config::dotPath+='/';
      } 
    } 
#if defined(_WIN32)
    QFileInfo dp(Config::dotPath+"dot.exe");
#else
    QFileInfo dp(Config::dotPath+"dot");
#endif
    if (!dp.exists() || !dp.isFile())
    {
      err("Warning: the dot tool could not be found at %s\n",Config::dotPath.data());
    }
  }
  else // make sure the string is empty but not null!
  {
    Config::dotPath="";
  }
  
  // check input
  if (Config::inputSources.count()==0)
  {
    err("Error: tag INPUT: no input files specified after the INPUT tag.\n");
    exit(1);
  }
  else
  {
    s=Config::inputSources.first();
    while (s)
    {
      QFileInfo fi(s);
      if (!fi.exists())
      {
	err("Error: tag INPUT: input source `%s' does not exist\n",s);
	exit(1);
      }
      s=Config::inputSources.next();
    }
  }

  // add default pattern if needed
  if (Config::filePatternList.isEmpty())
  {
    Config::filePatternList.append("*");
  }

  // add default pattern if needed
  if (Config::examplePatternList.isEmpty())
  {
    Config::examplePatternList.append("*");
  }

  // add default pattern if needed
  //if (Config::imagePatternList.isEmpty())
  //{
  //  Config::imagePatternList.append("*");
  //}
  
  // more checks needed if and only if the search engine is enabled.
  if (Config::searchEngineFlag)
  {
    // check cgi name
    if (Config::cgiName.isEmpty())
    {
      err("Error: tag CGI_NAME: no cgi script name after the CGI_NAME tag.\n");
      exit(1);
    }
    // check cgi URL
    if (Config::cgiURL.isEmpty())
    {
      err("Error: tag CGI_URL: no URL to cgi directory specified.\n");
      exit(1);
    }
    else if (Config::cgiURL.left(7)!="http://" && 
	     Config::cgiURL.left(8)!="https://"
	    )
    {
      err("Error: tag CGI_URL: URL to cgi directory is invalid (must "
	  "start with http:// or https://).\n");
      exit(1);
    }
    // check documentation URL
    if (Config::docURL.isEmpty())
    {
      Config::docURL = Config::outputDir.copy().prepend("file://").append("html");
    }
    else if (Config::docURL.left(7)!="http://" && 
	     Config::docURL.left(8)!="https://" &&
	     Config::docURL.left(7)!="file://"
	    )
    {
      err("Error: tag DOC_URL: URL to documentation is invalid or "
	  "not absolute.\n"); 
      exit(1);
    }
    // check absolute documentation path
    if (Config::docAbsPath.isEmpty())
    {
      Config::docAbsPath = Config::outputDir+"/html"; 
    }
    else if (Config::docAbsPath[0]!='/' && Config::docAbsPath[1]!=':')
    {
      err("Error: tag DOC_ABSPATH: path is not absolute!\n");
      exit(1);
    }
    // check path to doxysearch
    if (Config::binAbsPath.isEmpty())
    {
      err("Error: tag BIN_ABSPATH: no absolute path to doxysearch "
	  "specified.\n");
      exit(1);
    }
    else if (Config::binAbsPath[0]!='/' && Config::binAbsPath[1]!=':')
    {
      err("Error: tag BIN_ABSPATH: path is not absolute!\n");
      exit(1);
    }

    // check perl path
    bool found=FALSE;
    if (Config::perlPath.isEmpty())
    {
      QFileInfo fi;
      fi.setFile("/usr/bin/perl");
      if (fi.exists()) 
      {
	Config::perlPath="/usr/bin/perl";
        found=TRUE;
      }
      else
      {
	fi.setFile("/usr/local/bin/perl");
	if (fi.exists())
        {
  	  Config::perlPath="/usr/local/bin/perl";
          found=TRUE;
        }
      }
    }
    if (!found)
    {
      QFileInfo fi(Config::perlPath);
      if (!fi.exists())
      {
        warn_cont("Warning: tag PERL_PATH: perl interpreter not found at default or"
            "user specified (%s) location\n",
        Config::perlPath.data());
      }
    }
  }

#if defined(_WIN32)
  if (Config::haveDotFlag) _putenv("DOTFONTPATH=.");
#endif
  
}

void parseConfig(const QCString &s,const char *fn)
{
  inputString   = s;
  inputPosition = 0;
  yyLineNr      = 1;
  yyFileName=fn;
  includeStack.setAutoDelete(TRUE);
  includeStack.clear();
  includeDepth  = 0;
  configYYrestart( configYYin );
  BEGIN( Start );
  configYYlex();
}

//extern "C" { // some bogus code to keep the compiler happy
//  int  configYYwrap() { return 1 ; }
//}