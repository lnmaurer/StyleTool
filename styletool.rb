#!/usr/bin/ruby

#styletool -- a simple word frequency based stylometry tool
#Copyright (C) 2008  Leon N. Maurer

#This program is free software; you can redistribute it and/or
#modify it under the terms of the GNU General Public License
#version 2 as published by the Free Software Foundation;

#This program is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.

#A copy of the license is available at 
#<http://www.gnu.org/licenses/old-licenses/gpl-2.0.html>
#You can also receive a paper copy by writing the Free Software
#Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

require 'tk'
require 'yaml' #needs to be before gsl?
require 'gsl'
#require 'gnuplot'
require 'tkextlib/tile/treeview'
require 'tempfile'

def max(n,m)
  n > m ? n : m
end

class Document
  attr_reader :name, :author, :group, :wordCount, :countedWords
  def initialize(name, author, group, text)
    @name = name
    @author = author
    @group = group
    @countedWords = Hash.new(0)
    words = text.downcase.scan(/\w+/) #doesn't catch contractions
    words.each{|word| @countedWords[word] += 1}
    @wordCount = words.size
  end
  def words
    @countedWords.keys
  end
  def count(word)
    #will return 0 if 'word' not in 'countedWords' since 0 is the default value
    @countedWords[word]
  end
  def relativeFrequency(word)
    @countedWords[word] / @wordCount.to_f
  end
  def <=>(other) #used for sorting
    if @author == other.author
      @name <=> other.name
    else
      @author <=> other.author
    end 
  end
end


class PCAtool
  attr_reader :matrix
  def initialize(vectors)
    @matrix = GSL::Matrix.alloc(vectors.flatten, vectors.size, vectors[0].size).transpose
  end
  def center
    avg = GSL::Vector.calloc(@matrix.size1) #calloc initalizes all values to 0
    for r in 0..(@matrix.size1 - 1)
      for c in 0..(@matrix.size2 - 1)
        avg[r] += @matrix[r,c] / @matrix.size2.to_f
      end
    end
    avg
  end
  def centeredMatrix
    cm = @matrix.duplicate
    avg = self.center
     for r in 0..(@matrix.size1 - 1)
      for c in 0..(@matrix.size2 - 1)
        cm[r,c] -= avg[r]
      end
    end
    cm
  end
  def scatterMatrix
    cm = self.centeredMatrix
    cm*cm.transpose  
  end
  def reduceDimensions(dims)
    vecs = Array.new(@matrix.size2){Array.new(dims)}
    eigval, eigvec = self.scatterMatrix.eigen_symmv
    cm = self.centeredMatrix
    for c in 0..(@matrix.size2 - 1)
      for e in 0..(dims - 1)
        vecs[c][e] = cm.col(c).row*eigvec.col(e)
      end
    end
    vecs
  end
end

class Interface
  attr_reader :documents
  @@ConfigFile = ".styletoolconfig"
  def initialize
    @documents = Array.new
    @masterWordList = Array.new

    #first, all the procs for use by the GUI
    quit = proc {
      settings = {"UseWordList" => (@wordListSpecified.get_value == "1"),
                 "PCAdims" => @pcaspinbox.get.to_i,
                 "WordList" => @masterWordList,
                 "ChunkSize"=>@chunkSize.get.to_i,
                 "SaveChunks"=> (@saveChunks.get_value == "1")}
      File.open(@@ConfigFile, "w"){|file| file.print(settings.to_yaml)}
      Process.exit
    }
    addfile = proc {
      filename = Tk.getOpenFile
      savefoldername = ""
      savefoldername = Tk.chooseDirectory("title"=>"Choose folder to save chunks to") if @saveChunks.get_value == "1"
      if @chunkSize.get.to_i == 0 #don't chunk
        #if the user clicks "cancel" in the dialog box then filename == ""
        self.addFile(filename,@author.value) unless filename == ""
      else #chunk
        self.chunkAndAddFile(filename,@author.value,savefoldername) unless filename == ""
      end
    }
    addfolder = proc {
      foldername = Tk.chooseDirectory("title"=>"Choose folder to add files from")
      savefoldername = ""
      savefoldername = Tk.chooseDirectory("title"=>"Choose folder to save chunks to") if @saveChunks.get_value == "1"
      if @chunkSize.get.to_i == 0 #don't chunk
        self.addFolder(foldername,@author.value) unless foldername == ""
      else #chunk
        self.chunkAndAddFolder(foldername,@author.value,savefoldername) unless foldername == ""
      end
    }
    remove = proc {
      self.remove(@tree.focus_item)
    }
    save = proc {
      filename = Tk.getSaveFile("filetypes"=>[["CSV", ".csv"]])
      self.saveToCSV(filename) unless filename == ""
    }
    plotpca = proc {
      self.plotPCA
    }
    explorepca = proc {
      self.explorePCA
    }
    savepca = proc {
      filename = Tk.getSaveFile("filetypes"=>[["CSV", ".csv"]])
      self.savePCAtoCSV(filename,@pcaspinbox.get.to_i) unless filename == ""
    }
    specifiywordlist = proc {
      if @atype.to_s == 'freq'
        @wlist = false
      else #we've selected to specify a word list
      filename = Tk.getOpenFile
        unless filename == ""
          @masterWordList = File.read(filename).downcase.scan(/\w+/).uniq
          @wlist = true
        else #the user hit 'cancel'
          if @wlist == false #we were previously using frequency
            @atype.set_value('freq')
          end
        end
      end
    }


    #and now for the GUI
    #the last bit calls the quit proc when the window is closed
    @root = TkRoot.new(){title 'Style Tool'}.protocol('WM_DELETE_WINDOW', quit)

    #the frames:
    fframe = TkLabelFrame.new(@root,:text=>'Files').grid(:column=>0,:row=>0,:columnspan=>2,:sticky=>'nsew',:padx=>5,:pady=>5)
    aframe = TkLabelFrame.new(@root,:text=>'Analysis').grid(:column=>2,:row=>0,:sticky=>'nsew',:padx=>5,:pady=>5)
    cframe = TkLabelFrame.new(@root,:text=>'Console').grid(:column=>0,:row=>1,:columnspan=>3,:sticky=>'nsew',:padx=>5,:pady=>5)

    #file frame

#TODO: horizontal scroll bar? change width and height?
    yscroll = proc{|*args| @lbscroll.set(*args)}
    scroll = proc{|*args| @tree.yview(*args)}
    @tree = Tk::Tile::Treeview.new(fframe){
      yscrollcommand yscroll
      selectmode 'browse'
    }.grid(:column=>0,:row=> 0,:columnspan=>3, :sticky=>'we')

    @lbscroll = TkScrollbar.new(fframe) {
      orient 'vertical'
      command scroll
    }.grid('column'=>4, 'row'=>0,'sticky'=>'wns')

    TkLabel.new(fframe){
      text "Author:"
    }.grid('column'=>0,'row'=>1, 'sticky'=>'w')

    @author = TkVariable.new()
    authorDisp = TkEntry.new(fframe) {
      width 30
      relief  'sunken'
    }.grid('column'=>1,'row'=> 1, 'sticky'=>'w', 'padx'=>5, 'pady'=>5)
    authorDisp.textvariable(@author)
    @author.value = 'Unknown'

    TkButton.new(fframe) {
      text    'Remove'
      command remove
    }.grid('column'=>0, 'row'=>2,'sticky'=>'w', 'padx'=>5, 'pady'=>5)

    TkButton.new(fframe) {
      text    'Add file'
      command addfile
    }.grid('column'=>1, 'row'=>2,'sticky'=>'w', 'padx'=>5, 'pady'=>5)
    TkButton.new(fframe) {
      text    'Add folder'
      command addfolder
    }.grid('column'=>2, 'row'=>2,'sticky'=>'w', 'padx'=>5, 'pady'=>5)
    
    TkLabel.new(fframe){
      text "Chunk size (words):"
    }.grid('column'=>0,'row'=>3, 'sticky'=>'e', 'padx'=>5, 'pady'=>5)

    @chunkSize = TkSpinbox.new(fframe) {
      to 100000
      from 100
      increment 100
      width 5
    }.grid('column'=>1,'row'=>3, 'sticky'=>'w', 'padx'=>5, 'pady'=>5)
    @chunkSize.set(1000) #a good default value

    @saveChunks = TkCheckButton.new(fframe){
      text "Save file chunks?"
    }.grid('column'=>2,'row'=> 3, 'sticky'=>'w')


    #analysis frame

    TkLabel.new(aframe){
      text "PCA dimensions:"
    }.grid('column'=>0,'row'=>0, 'sticky'=>'w', 'padx'=>5, 'pady'=>5)
    @pcaspinbox = TkSpinbox.new(aframe) {
      to 50
      from 1
      increment 1
      width 4
    }.grid('column'=>1,'row'=>0, 'sticky'=>'w', 'padx'=>5, 'pady'=>5)
    @pcaspinbox.set(2) #a good default value

    TkButton.new(aframe) {
      text    'Save word frequencies as CSV'
      command save
    }.grid('column'=>0, 'row'=>1,'columnspan'=>2,'sticky'=>'w', 'padx'=>5, 'pady'=>5)
    TkButton.new(aframe) {
      text    'Save PCA as CSV'
      command savepca
    }.grid('column'=>0, 'row'=>2,'columnspan'=>2,'sticky'=>'w', 'padx'=>5, 'pady'=>5)
    TkButton.new(aframe) {
      text    'Plot 2D PCA'
      command plotpca
    }.grid('column'=>0, 'row'=>3,'columnspan'=>2,'sticky'=>'w', 'padx'=>5, 'pady'=>5)
    TkButton.new(aframe) {
      text    'Explore 2D PCA'
      command explorepca
    }.grid('column'=>0, 'row'=>4,'columnspan'=>2,'sticky'=>'w', 'padx'=>5, 'pady'=>5)

    TkLabel.new(aframe){
      text "Analysis type:"
    }.grid('column'=>0,'row'=>5, 'sticky'=>'w', 'padx'=>5, 'pady'=>5)

    @atype = TkVariable.new
    @atype.set_value('freq')
    @wlist = false #to store previous state of radio buttons
#TODO: commands for these
    TkRadioButton.new(aframe,:text=>'Use Word List',:variable=>@atype,:value=>'list',:command=>specifiywordlist).grid('column'=>0, 'row'=>6,'columnspan'=>2,'sticky'=>'w', 'padx'=>5, 'pady'=>5)
    TkRadioButton.new(aframe,:text=>'X Most Frequently Used Words',:variable=>@atype,:value=>'freq',:command=>specifiywordlist).grid('column'=>0, 'row'=>7,'columnspan'=>2,'sticky'=>'w', 'padx'=>5, 'pady'=>5)

    TkLabel.new(aframe){
      text "X:"
    }.grid('column'=>0,'row'=>8, 'sticky'=>'w', 'padx'=>5, 'pady'=>5)
    @wordstocount = TkSpinbox.new(aframe) {
      to 200
      from 1
      increment 1
      width 4
    }.grid('column'=>1,'row'=>8, 'sticky'=>'w', 'padx'=>5, 'pady'=>5)
    @wordstocount.set(50) #a good default value

    #console frame
    cyscroll = proc{|*args| @cscrollb.set(*args)}
    cscroll = proc{|*args| @console.yview(*args)}
    @console = TkText.new(cframe,:yscrollcommand=>cyscroll,:width=>80,:height=>10).grid(:column=>0,:row=>0,:padx=>5,:pady=>5)
    @cscrollb = TkScrollbar.new(cframe,:orient=>'vertical',:command=>cscroll).grid(:column=>1,:row=>0,:padx=>5,:sticky=>'ns')



    #top row (output commands)



    #second row (more PCA)


    
    #3rd row (file treeview)
    
    
    #4th row (author)

    
    #5th row (specify wordlist)
    
#     @wordListSpecified = TkCheckButton.new(@root){
#       text "Count specific words only"
#       command wordlisttoggled
#     }.grid('column'=>1,'row'=> 4, 'sticky'=>'w')
    
    #6th row (adding files)
    


    #7th row (chunking)
#     TkButton.new(@root) {
#       text    'Chunk and add file'
#       command chunkaddfile
#     }.grid('column'=>0, 'row'=>6,'sticky'=>'w', 'padx'=>5, 'pady'=>5)
#     TkButton.new(@root) {
#       text    'Chunk and add folder'
#       command chunkaddfolder
#     }.grid('column'=>1, 'row'=>6,'sticky'=>'w', 'padx'=>5, 'pady'=>5)   
    
    #8th row (chunking settings)




    #END GUI
    #load settings from config file if it exists
    #if there's none to load, the default values are built in to the code
#TODO: update this for new GUI
#     if File.file?(@@ConfigFile)
#       #TODO: error handling for YAML
#       settings = YAML.load(File.open(@@ConfigFile))
#       if settings["UseWordList"]
#         @wordListSpecified.set_value("1")
#         @masterWordList = settings["WordList"]
#       end
#       @pcaspinbox.set(settings["PCAdims"])
#       if settings["ChunkDocs"]
#         @chunkDocs.set_value("1")
#         @chunkSize.state('normal')
#       end
#       @chunkSize.set(settings["ChunkSize"])
#       @saveChunks.set_value('1') if settings["SaveChunks"]
#     end

  end

#TODO: impliment this
  #this is called at analysis time
  def generateMasterWordList
    #ONLY GENERATE A NEW WORD LIST IF WE'RE DOING 'X MOST POPULAR WORDS'
    #WORD LIST WILL ALREADY BE LOADED OTHERWISE
    #@masterWordList = 

  end

#   def specifyWordList(filename)
#     @masterWordList = File.read(filename).downcase.scan(/\w+/).uniq
#     self.reload
#   end
#   def unspecifyWordList
#     @masterWordList = Array.new
#     self.reload
#   end

  def doPCA(dims)
    self.generateMasterWordList
    PCAtool.new(self.coords).reduceDimensions(dims)
  end
  def reload
    docinfo = @documents.collect{|doc| [doc.name,doc.author]}
    #clear everything
    @documents = Array.new
    @tree.children("").each{|item| @tree.delete(item)}
    #reload it
    docinfo.each{|filename,author| self.addFile(filename,author)}
  end
  def readFile(filename)
    #removes comments  
    File.read(filename).gsub(/<(.|\s)*?>/,'')
  end
  def addFile(filename,author)
    addDoc(self.readFile(filename),filename,author)
  end
  def addDoc(text,filename,author)
    if @tree.exist?(filename)
      Tk.messageBox('type' => 'ok',
        'icon' => 'error',
        'title' => 'File already included',
        'message' => "A file named #{filename} has already been added -- you cannot add the same file more than once.")
      return #exits the function
    end

    #add author if need be
    unless @tree.exist?(author)
      authors = @tree.children("").collect{|item| item.id}
      i = 0
      while (i < authors.size) and (author.casecmp(authors[i]) == 1)
        i += 1
      end
      @tree.insert('', i, :id => author, :text => author)
    end

    #id is the full path but text is just the file name
    name = filename.split(File::SEPARATOR).pop
    #the group is the filename without the chunk number
    group = name.gsub(/[.]\d+/,'')
    names = @tree.children(author).collect{|item| item.id.split(File::SEPARATOR).pop}
    i = 0
    while (i < names.size) and (name.casecmp(names[i]) == 1)
      i += 1
    end
    @tree.insert(author, i, :id => filename, :text => name)

    @documents << Document.new(filename,author,group,text)
    @documents = @documents.sort #keeps everything sorted
  end
  def chunkAndAddFile(filename,author,savedir="")
    name = filename.split(File::SEPARATOR).pop
    text = self.readFile(filename).split
    chunks = Array.new
    while text.size >= @chunkSize.get.to_i
      chunks << text.slice!(0,@chunkSize.get.to_i).join(' ')
    end
    
    if chunks.size == 0 #document too short
      #TODO: pop up message?
      return
    end
    
    #make an array of chunks
    if savedir == "" #save chunks to tempfiles
      chunks.each_with_index{|chunk,i|
        Tempfile.open(name + '.' + i.to_s){|f| f.print(chunk)}
        self.addDoc(chunk,filename + '.' + i.to_s,author)
      }
    else #save them to real files
      chunks.each_with_index{|chunk,i|
        savefile = savedir + File::SEPARATOR + name + '.' + i.to_s
        File.open(savefile,"w"){|f| f.print(chunk)}
        self.addDoc(chunk,savefile,author)
      }
    end
  end
  def addFolder(path,author)
    #add path to keep things consistant with adding single files
    Dir.chdir(path){Dir.foreach(path){|file| self.addFile(path + File::SEPARATOR + file,author) if File.file?(file)}}
  end
  def chunkAndAddFolder(path,author,savedir="")
    Dir.chdir(path){Dir.foreach(path){|file| self.chunkAndAddFile(path + File::SEPARATOR + file,author,savedir) if File.file?(file)}}
  end
  def remove(item)
    if @documents.collect{|doc| doc.author}.include?(item.id) #have we slected all works by the author?
      @documents.reject!{|doc| doc.author == item.id}
    else #it's a file
      @documents.reject!{|doc| doc.name == item.id}
    end
#     unless @wordListSpecified.get_value == '1'
#       @masterWordList = @documents.inject([""]){|words,doc| words |doc.words}
#     end
    @tree.delete(item)
  end
  def coords
    self.generateMasterWordList
    @documents.collect{|doc| @masterWordList.collect{|word| doc.relativeFrequency(word)}}
  end
  def saveToCSV(filename)
    self.generateMasterWordList
    File.open(filename, "w") do |file|
      #prints the file name at the top of each column
      @documents.each{|doc| file.print(",",doc.author)}
      file.print("\n")
      @documents.each{|doc| file.print(",",doc.name)}
      file.print("\n")
      @masterWordList.each do |word|
        file.print(word)
        @documents.each{|doc| file.print(",",doc.relativeFrequency(word))}
        file.print("\n")
      end
    end
  end

  @@GraphColors = ['Red', 'Green', 'Blue', 'Magenta', 'Cyan']     

 def plotPCA                                                                                  
   authors = @documents.collect{|doc| doc.author}.uniq                                        
   #the following gives [ ['author',[x,y]], ...]                                              
   c = @documents.collect{|doc| doc.author}.zip(self.doPCA(2))                                
   tfiles = authors.collect do |author|                                                       
     tf = Tempfile.new(author)                                                                
     c.find_all{|arr| arr[0] == author}.each{|coords| tf.print(coords[1][0]," ",coords[1][1])}
     tf.close                                                                                 
     tf #need to return tf at the end                                                         
   end                                                                                        
 #TODO: change this? only a couple of colors are available.                                   
 #TODO: Make a key for the colors                                                             
 #TODO: use canvas instead of another program? canvas can output to postscript...             
   color = 0                                                                                  
   command = tfiles.inject("graph -T X -C"){|command,tf| command + " -m -#{color+=1} -S 3 " + '"' + tf.path + '"'}
   #'"' are to put quotes around the name, incase there is a space in it                                          
   color = -1                                                                                                     
   command += authors.inject(" -L \""){|command, auth| command + " #{auth} #{@@GraphColors[color+=1]} "} + '"'    
   IO.popen(command, "w")                                                                                         
   responce = Tk::messageBox(                                                                                     
     'type' => 'yesno',                                                                                           
     'message' => 'Do you wish to save this plot?',                                                               
     'icon' => 'question',                                                                                        
     'title' => 'Save plot?')                                                                                     
   if responce == 'yes'                                                                                           
     filename = Tk.getSaveFile("filetypes"=>[["PS", ".ps"],["PNG",".png"],["SVG",".svg"]])                        
#      self.savePlot(filename) unless filename == ""                                                               
     color = 0                                                                                                    
     command = tfiles.inject("graph -T #{filename.split(".").pop} -C"){|command,tf| command + " -m -#{color+=1} -S 3 " + '"' + tf.path + '"'}
     color = -1                                                                                                                              
     command += authors.inject(" -L \""){|command, auth| command + " #{auth} #{@@GraphColors[color+=1]} "} + "\" > #{filename}"              
     IO.popen(command, "w")                                                                                                                  
   end
  end


  def explorePCA
    authors = @documents.collect{|doc| doc.author}.uniq

    n = @documents.collect{|doc| doc.name}
    a = @documents.collect{|doc| doc.author}
    g = @documents.collect{|doc| doc.group}

    p = Plot.new(@root)
    #the following makes [ [[x,y],'name','author','group'], ...], then makes points from it
    self.doPCA(2).zip(n,a,g).each{|coord,name,author,group| p.add(coord[0],coord[1],name,author,group)}
    p.refresh
  end
#  def savePlot(filename)
#puts filename
#  end
  def savePCAtoCSV(filename,dims)
    pca = self.doPCA(dims)
    File.open(filename, "w") do |file|
      @documents.zip(pca).each do |doc,coords|
        file.print(doc.author,",")
        file.print(doc.name,",")
        coords.each{|coord| file.print(coord,",")}
        file.print("\n")
      end
    end    
  end
end


class Plot < TkToplevel

  @@CanvasSize = 500
#TODO: make a way to give the window a name
  def initialize(parent)
    super(parent)
    @items = Array.new
  end

  def add(x,y,name,group,subgroup)
#    print x," ",y,"\n"
    @items << Point.new(x,y,name,group,subgroup)
  end

  def refresh
    @canvas = TkCanvas.new(self) {
      width @@CanvasSize
      height @@CanvasSize
    }.grid('column'=>0,'row'=> 0, 'sticky'=>'nsew')
    @name = TkVariable.new()
    nameDisp = TkEntry.new(self) {
      width 30
      relief  'sunken'
    }.grid('column'=>0,'row'=> 1, 'sticky'=>'n', 'padx'=>5, 'pady'=>5)
    nameDisp.textvariable(@name)
    @name.value = 'none selected'
    closest = proc{|x, y|
      c = @items.sort_by{|item|
        xp = ((1 + item.x/@maxsize)*@@CanvasSize/2)
        yp = ((1 + item.y/@maxsize)*@@CanvasSize/2)
        ((x-xp)**2 + (y-yp)**2)**0.5
      }[0]
      @name.value = c.group + ': ' + c.name.split(File::SEPARATOR).pop
      @canvas.delete('linetoclosest')
      xp = ((1 + c.x/@maxsize)*@@CanvasSize/2)
      yp = ((1 + c.y/@maxsize)*@@CanvasSize/2)
      TkcLine.new(@canvas, x, y, xp, yp, :fill => 'black', :width => 1, :tags => 'linetoclosest')    
    }

    @canvas.bind("Motion", closest, "%x %y")

    #size is the largest coordiante plus a bit
    @maxsize = @items.inject(0){|largest,item| max(max(item.x,item.y),largest)} * 1.05
    groups = @items.collect{|item| item.group}.sort

    groups.each_with_index{|group,i|
      ingroup = @items.reject{|item| item.group != group}
      subgroups = ingroup.collect{|item| item.subgroup}.sort
      subgroups.each_with_index{|subgroup,j|
        insubgroup = ingroup.reject{|item| item.subgroup != subgroup}
        insubgroup.each{|item|
          r,g,b = color(i,groups.size,j,subgroups.size)
          self.point(item.x,item.y,r,g,b)
        }
      }
    }

   #draw axis
   TkcLine.new(@canvas, 0, @@CanvasSize/2, @@CanvasSize, @@CanvasSize/2, :fill => 'black', :width => 1)
   TkcLine.new(@canvas, @@CanvasSize/2, 0, @@CanvasSize/2, @@CanvasSize, :fill => 'black', :width => 1)

   TkcLine.new(@canvas, 0, 0, 0, 0, :fill => 'black', :width => 1, :tags => 'linetoclosest')

  end
  def point(x,y,r,g,b)
    #print x," ",y," ",r," ",g," ",b,"\n"
    rs = (r*255).round.to_s(16)
    if rs.length == 1
      rs = '0' + rs
    end
    gs = (g*255).round.to_s(16)
    if gs.length == 1
      gs = '0' + gs
    end
    bs = (b*255).round.to_s(16)
    if bs.length == 1
      bs = '0' + bs
    end

    color = '#' + rs + gs + bs
#print color + "\n"
    xp = ((1 + x/@maxsize)*@@CanvasSize/2).round
    yp = ((1 + y/@maxsize)*@@CanvasSize/2).round
    TkcLine.new(@canvas, xp-5, yp, xp+5, yp, :fill => color, :width => 1)
    TkcLine.new(@canvas, xp, yp-5, xp, yp+5, :fill => color, :width => 1)
  end
  def color(i,hues,j,saturations)
    h = 360 * (i/hues.to_f)
    s = 0.75 + 0.25 * (j/saturations.to_f)
    v = 0.5 + 0.5 * (j/saturations.to_f)

    #convert to RGB
    hi = (h/60.0).floor % 6
    f = (h/60.0) - (h/60.0).floor

    p = v*(1.0 - s)
    q = v*(1.0 - s * f)
    t = v*(1.0 - (1-f) * s)

    case hi
      when 0: [v,t,p]
      when 1: [q,v,p]
      when 2: [p,v,t]
      when 3: [p,q,v]
      when 4: [t,p,v]
      when 5: [v,p,q]
    end
  end
end

class Point
  attr_reader :x, :y, :name, :group, :subgroup
  def initialize(x,y,name,group,subgroup)
    @x = x
    @y = y
    @name = name
    @group = group
    @subgroup = subgroup
  end
end

if __FILE__ == $0
  Interface.new
  Tk.mainloop()
end