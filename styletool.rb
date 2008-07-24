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

class Document
  attr_reader :name, :author, :wordCount, :countedWords
  def initialize(name, author, text)
    @name = name
    @author = author
    @countedWords = Hash.new(0)
    words = text.downcase.scan(/\w+/) #doesn't catch contractions
    if block_given?
      words.each{|word| @countedWords[word] += 1 if yield(word)}
    else
      words.each{|word| @countedWords[word] += 1}
    end
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
    @matrix = Matrix.alloc(vectors.flatten, vectors.size, vectors[0].size).transpose
  end
  def center
    avg = Vector.calloc(@matrix.size1) #calloc initalizes all values to 0
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

    quit = proc {
      settings = {"UseWordList" => (@wordListSpecified.get_value == "1"),"PCAdims" => @pcaspinbox.get.to_i,"WordList" => @masterWordList}
      File.open(@@ConfigFile, "w"){|file| file.print(settings.to_yaml)}
      Process.exit
    }

    #and now for the GUI
    @root = TkRoot.new(){title 'Style Tool'}.protocol('WM_DELETE_WINDOW', quit)

    addfile = proc {
      filename = Tk.getOpenFile
      #if the user clicks "cancel" in the dialog box then filename == ""
      self.addFile(filename,@author.value) unless filename == ""
    }
    addfolder = proc {
      foldername = Tk.chooseDirectory
      self.addFolder(foldername,@author.value) unless foldername == ""
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
    savepca = proc {
      filename = Tk.getSaveFile("filetypes"=>[["CSV", ".csv"]])
      self.savePCAtoCSV(filename,@pcaspinbox.get.to_i) unless filename == ""
   }
    TkButton.new(@root) {
      text    'Add file'
      command addfile
    }.grid('column'=>0, 'row'=>5,'sticky'=>'w', 'padx'=>5, 'pady'=>5)
    TkButton.new(@root) {
      text    'Add folder'
      command addfolder
    }.grid('column'=>1, 'row'=>5,'sticky'=>'w', 'padx'=>5, 'pady'=>5)
    TkButton.new(@root) {
      text    'Remove'
      command remove
    }.grid('column'=>2, 'row'=>5,'sticky'=>'w', 'padx'=>5, 'pady'=>5)
    TkButton.new(@root) {
      text    'Save as CSV'
      command save
    }.grid('column'=>0, 'row'=>0,'sticky'=>'w', 'padx'=>5, 'pady'=>5)
    TkButton.new(@root) {
      text    'plot 2D PCA'
      command plotpca
    }.grid('column'=>1, 'row'=>0,'sticky'=>'w', 'padx'=>5, 'pady'=>5)
    TkButton.new(@root) {
      text    'Save PCA as CSV'
      command savepca
    }.grid('column'=>2, 'row'=>0,'sticky'=>'w', 'padx'=>5, 'pady'=>5)

    TkLabel.new{
      @root
      text "PCA dimensions:"
    }.grid('column'=>1,'row'=>1, 'sticky'=>'e', 'padx'=>5, 'pady'=>5)
    @pcaspinbox = TkSpinbox.new(@root) {
      to 50
      from 1
      increment 1
      width 4
    }.grid('column'=>2,'row'=>1, 'sticky'=>'w', 'padx'=>5, 'pady'=>5)
    @pcaspinbox.set(2) #a good default value

    wordlisttoggled = proc {
      if @wordListSpecified.get_value == "1"
        filename = Tk.getOpenFile
        unless filename == ""
          self.specifyWordList(filename)
        else #the user hit 'cancel' -- don't change anything!
          @wordListSpecified.set_value("0")
        end
      else
        self.unspecifyWordList
      end
    }
    @wordListSpecified = TkCheckButton.new(@root){
      text "Count specific words only"
      command wordlisttoggled
    }.grid('column'=>1,'row'=> 4, 'sticky'=>'w')

    TkLabel.new{
      @root
      text "Loaded files:"
    }.grid('column'=>0,'row'=>2, 'sticky'=>'w')

#TODO: horizontal scroll bar? change width and height?
    yscroll = proc{|*args| @lbscroll.set(*args)}
    scroll = proc{|*args| @tree.yview(*args)}
    @tree = Tk::Tile::Treeview.new(@root){
      yscrollcommand yscroll
      selectmode 'browse'
    }.grid('column'=>1,'row'=> 2, 'sticky'=>'we')

    @lbscroll = TkScrollbar.new(@root) {
      orient 'vertical'
      command scroll
    }.grid('column'=>2, 'row'=>2,'sticky'=>'wns')

    TkLabel.new{
      @root
      text "Author:"
    }.grid('column'=>0,'row'=>3, 'sticky'=>'w')

    @author = TkVariable.new()
    authorDisp = TkEntry.new(@root) {
      width 30
      relief  'sunken'
    }.grid('column'=>1,'row'=> 3, 'sticky'=>'w', 'padx'=>5, 'pady'=>5)
    authorDisp.textvariable(@author)
    @author.value = 'Unknown'

    #load settings from config file if it exists
    if File.file?(@@ConfigFile)
      #TODO: error handling for YAML
      settings = YAML.load(File.open(@@ConfigFile))
      if settings["UseWordList"]
        @wordListSpecified.set_value("1")
        @masterWordList = settings["WordList"]
      end
      @pcaspinbox.set(settings["PCAdims"])
    end

  end
  def doPCA(dims)
    PCAtool.new(self.coords).reduceDimensions(dims)
  end
  def specifyWordList(filename)
    @masterWordList = IO.read(filename).downcase.scan(/\w+/).uniq
    self.reload
  end
  def unspecifyWordList
    @masterWordList = Array.new
    self.reload
  end
  def reload
    docinfo = @documents.collect{|doc| [doc.name,doc.author]}
    #clear everything
    @documents = Array.new
    @tree.children("").each{|item| @tree.delete(item)}
    #reload it
    docinfo.each{|filename,author| self.addFile(filename,author)}
  end
  def addFile(filename,author)
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
    name = filename.split('/').pop
    names = @tree.children(author).collect{|item| item.id.split('/').pop}
    i = 0
    while (i < names.size) and (name.casecmp(names[i]) == 1)
      i += 1
    end
    @tree.insert(author, i, :id => filename, :text => name)

    if @wordListSpecified.get_value == '1'
      newdoc = Document.new(filename,author,IO.read(filename)) {|word| @masterWordList.include?(word)}
    else
      newdoc = Document.new(filename,author,IO.read(filename))
      @masterWordList = (@masterWordList | newdoc.words).sort
    end
    @documents.push(newdoc)
    @documents = @documents.sort #keeps everything sorted
  end
  def addFolder(path,author)
    #add path to keep things consistant with adding single files
    Dir.chdir(path){Dir.foreach(path){|file| self.addFile(path + '/' + file,author) if File.file?(file)}}
  end
  def remove(item)
    if @documents.collect{|doc| doc.author}.include?(item.id) #have we slected all works by the author?
      @documents.reject!{|doc| doc.author == item.id}
    else #it's a file
      @documents.reject!{|doc| doc.name == item.id}
    end
    unless @wordListSpecified.get_value == '1'
      @masterWordList = @documents.inject([""]){|words,doc| words |doc.words}
    end
    @tree.delete(item)
  end
  def coords
    @documents.collect{|doc| @masterWordList.collect{|word| doc.relativeFrequency(word)}}
  end
  def saveToCSV(filename)
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


if __FILE__ == $0
  Interface.new
  Tk.mainloop()
end